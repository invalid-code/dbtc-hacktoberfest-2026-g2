"""Asks Gemini how the pumps should behave, from the weather and the state of the greenhouse.

There is no endpoint for this: the weather service calls it in the background
and the answer becomes the activation parameters of the pumps.

Gemini answers with json only, and the answer is checked again in
`irrigation_service` before it is stored, so a strange answer can never move
the parameters outside their limits.
"""

import json
import logging

from dataclasses import dataclass, field

import httpx

from app.config import settings
from app.modes import PumpModeName
from app.services.weather_service import Climate, Weather

logger = logging.getLogger(__name__)

GEMINI_API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)

# The modes the device can run, and what they give.
CHOICES = [PumpModeName.FAST.name, PumpModeName.SLOW.name, PumpModeName.DRIP.name]

SYSTEM_INSTRUCTION = (
    "You are the irrigation brain of a small greenhouse. You are given the "
    "weather of the next days, the climate normal of the place the greenhouse "
    "stands in, and the readings the sensors send every few seconds. You "
    "decide how each pump should behave.\n"
    "\n"
    "For every pump you decide:\n"
    "- activate: whether the pump may water at all. Say false when the soil "
    "is wet enough, when the weather is cold enough to hurt the plants, or "
    "when there is nothing to be done.\n"
    "- moisture_threshold: the target soil moisture percentage. A pump below "
    "it waters until it reaches it. A lower threshold waters sooner. Keep it "
    "between 15 and 45.\n"
    "- activation_interval_minutes: the minutes the pump has to wait between "
    "two activations. More water means longer waits. Keep it between 15 and "
    "720.\n"
    "- mode: how the pump delivers the water while it runs until the soil "
    "reaches the threshold. FAST is the strongest flow, SLOW is about half, "
    "DRIP is a pulsed trickle and SPRINKLE is not implemented on the device "
    "and must never be used.\n"
    "- reason: one short sentence, in plain words, saying why you chose this.\n"
    "\n"
    "Weigh the heat, the rain that is coming, the evaporation, how dry the "
    "soil already is, whether it is drying out or wetting up, and how much "
    "water the plant has had recently. When the soil is dry and it stays hot, "
    "water sooner and with more water. When rain is coming or the soil is wet "
    "enough, water later and with less. Never water a plant that is already "
    "wet enough.\n"
    "\n"
    "The soil moisture of a zone is given as the last real readings, oldest "
    "first. Sometimes the device publishes garbled readings, those are left "
    "out and the zone is marked, so judge the zone on the real numbers only.\n"
    "\n"
    "Answer with json only."
)

RESPONSE_SCHEMA = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "pump_id": {"type": "INTEGER"},
            "activate": {"type": "BOOLEAN"},
            "moisture_threshold": {"type": "INTEGER"},
            "activation_interval_minutes": {"type": "INTEGER"},
            "mode": {"type": "STRING", "enum": CHOICES},
            "reason": {"type": "STRING"},
        },
        "required": [
            "pump_id",
            "activate",
            "moisture_threshold",
            "activation_interval_minutes",
            "mode",
            "reason",
        ],
    },
}


class GeminiError(Exception):
    """Gemini could not be reached, or did not answer with what was asked for."""


@dataclass(frozen=True)
class ZoneState:
    """What one zone of the greenhouse looks like right now."""

    pump_id: int
    moisture: int | None
    humidity: int | None
    temperature: float | None
    minutes_since_last_watering: float | None
    liters_today: float
    # the soil moisture of the last real readings, oldest first
    recent_moisture: list[float] = field(default_factory=list)
    # how long ago the last real reading of the zone was taken
    reading_age_minutes: float | None = None
    # whether the latest reading of the zone was one of the garbled ones
    garbled_latest: bool = False


def gemini_configured() -> bool:
    """Whether an api key is set, and with it whether Gemini can be called."""
    return bool(settings.GEMINI_API_KEY)


def build_prompt(
    weather: Weather,
    climate: Climate,
    zones: list[ZoneState],
    current: dict[int, dict],
) -> str:
    """The facts Gemini decides on, in words."""
    lines = [
        "The weather of the next days:",
        f"  right now {weather.temperature:.1f} C, "
        f"{weather.humidity:.0f} % humidity",
    ]
    for index, (high, low, rain, evaporation) in enumerate(
        zip(
            weather.max_temperatures,
            weather.min_temperatures,
            weather.precipitation,
            weather.evaporation,
        ),
        start=1,
    ):
        lines.append(
            f"  day {index}: {high:.1f} C high, {low:.1f} C low, "
            f"{rain:.1f} mm of rain, {evaporation:.1f} mm of evaporation"
        )

    lines.append(
        f"The climate of the place over the last {climate.days} days: "
        f"{climate.mean_temperature:.1f} C on average, "
        f"{climate.mean_daily_precipitation:.1f} mm of rain and "
        f"{climate.mean_daily_evaporation:.1f} mm of evaporation a day"
    )

    lines.append("The zones of the greenhouse:")
    for zone in zones:
        lines.append(f"  pump {zone.pump_id}:")
        if zone.garbled_latest:
            lines.append(
                "    the latest reading is garbled, the numbers below are the "
                "last real ones"
            )
        if zone.moisture is None:
            lines.append("    no soil moisture reading yet")
        else:
            age = (
                f" ({zone.reading_age_minutes:.0f} minutes ago)"
                if zone.reading_age_minutes is not None
                else ""
            )
            lines.append(f"    {zone.moisture} % soil moisture{age}")
        if zone.humidity is not None and zone.temperature is not None:
            lines.append(f"    {zone.humidity} % humidity, {zone.temperature:.1f} C")
        if zone.recent_moisture:
            trend = ", ".join(f"{value:.0f}" for value in zone.recent_moisture)
            lines.append(f"    the soil moisture went {trend} %")
        if zone.minutes_since_last_watering is not None:
            lines.append(
                f"    watered {zone.minutes_since_last_watering:.0f} minutes ago"
            )
        else:
            lines.append("    never watered")
        lines.append(f"    {zone.liters_today:.2f} litres used today")

    if current:
        lines.append("The parameters the pumps run with right now:")
        for pump_id, parameters in sorted(current.items()):
            lines.append(
                f"  pump {pump_id}: waters at {parameters['moisture_threshold']} % "
                f"soil moisture, every {parameters['activation_interval_minutes']} "
                f"minutes, in {parameters['mode']} mode, "
                f"{'active' if parameters['active'] else 'not watering'}"
            )

    return "\n".join(lines)


async def decide_parameters(
    client: httpx.AsyncClient,
    weather: Weather,
    climate: Climate,
    zones: list[ZoneState],
    current: dict[int, dict] | None = None,
) -> dict[int, dict]:
    """Ask Gemini for the activation parameters of every pump.

    The answer is keyed by the pump id, so a pump Gemini did not talk about
    is simply missing from it.
    """
    if not gemini_configured():
        raise GeminiError("no GEMINI_API_KEY is set")

    payload = {
        "systemInstruction": {"parts": [{"text": SYSTEM_INSTRUCTION}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": build_prompt(weather, climate, zones, current or {})}
                ],
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
        },
    }

    url = GEMINI_API_URL.format(model=settings.GEMINI_MODEL)
    try:
        response = await client.post(
            url,
            headers={"x-goog-api-key": settings.GEMINI_API_KEY},
            json=payload,
            timeout=settings.GEMINI_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError as error:
        raise GeminiError(f"gemini could not be reached: {error}") from error

    if response.status_code >= 400:
        logger.warning(
            "the gemini request failed with status %s: %s",
            response.status_code,
            response.text,
        )
        raise GeminiError(f"gemini answered with status {response.status_code}")

    try:
        body = response.json()
    except ValueError as error:
        raise GeminiError("gemini did not answer with json") from error

    return _parse(body)


def _parse(body: dict) -> dict[int, dict]:
    """The decisions in the answer of Gemini, keyed by the pump id."""
    candidates = body.get("candidates") or []
    if not candidates:
        raise GeminiError("gemini did not answer with any candidate")

    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "".join(part.get("text", "") for part in parts).strip()
    if not text:
        raise GeminiError("gemini answered without any text")

    try:
        decisions = json.loads(text)
    except ValueError as error:
        raise GeminiError("gemini did not answer with valid json") from error

    if not isinstance(decisions, list):
        raise GeminiError("gemini did not answer with a list of decisions")

    keyed: dict[int, dict] = {}
    for decision in decisions:
        if not isinstance(decision, dict):
            continue
        pump_id = decision.get("pump_id")
        if isinstance(pump_id, int):
            keyed[pump_id] = decision
    return keyed
