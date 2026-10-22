"""The automatic irrigation: Gemini decides how the pumps behave.

A background task asks the outside sources how the next days will look and
how they usually look, tells Gemini together with the state of the
greenhouse, and writes down what Gemini decides:

* whether the pump may **activate** at all,
* the **moisture threshold** it waters at,
* the **activation interval** it has to wait,
* the **mode** it waters in, which is how much water one activation gives.

When there is no api key, or Gemini cannot be reached, the plain rules in
`compute_parameters` decide instead, so the greenhouse is never left without
parameters. Whatever comes back is clamped into the limits before it is
stored, so neither Gemini nor a strange day can ruin the plants.
"""

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import AsyncSessionLocal
from app.modes import MODE_INDEX, PumpModeName, mode_name
from app.repositories import parameter_repo, pump_repo, sensor_repo
from app.services import gemini_service, pump_service, weather_service
from app.services.gemini_service import ZoneState
from app.services.weather_service import Climate, Weather

logger = logging.getLogger(__name__)

# The parameters a pump starts with, before any weather was seen.
BASE_MOISTURE_THRESHOLD = 30
BASE_ACTIVATION_INTERVAL_MINUTES = 60

# How far the parameters may move, whatever Gemini says.
MIN_MOISTURE_THRESHOLD = 15
MAX_MOISTURE_THRESHOLD = 45
MIN_ACTIVATION_INTERVAL_MINUTES = 15
MAX_ACTIVATION_INTERVAL_MINUTES = 720

# How much of the usual rain a day of forecast rain is worth.
CLIMATE_DAYS_OF_RAIN = 3

# How far the demand may move, so that one strange day cannot ruin the plants.
MIN_DEMAND = 0.4
MAX_DEMAND = 2.5

# How many readings of a zone are shown to Gemini, so it can see the trend.
RECENT_READING_COUNT = 6


@dataclass(frozen=True)
class PumpParameters:
    """The activation parameters of one pump."""

    active: bool
    moisture_threshold: int
    activation_interval_minutes: int
    mode: int
    reason: str


def compute_parameters(weather: Weather, climate: Climate) -> PumpParameters:
    """Work out the activation parameters the current conditions call for.

    This is the fallback for when Gemini is not there: the demand says how
    much water the plants need compared to a usual day, a hotter and drier
    forecast than usual asks for more water and rain that is coming asks for
    less.
    """
    heat = weather.mean_max_temperature - climate.mean_temperature
    evaporation = weather.mean_evaporation - climate.mean_daily_evaporation
    usual_rain = climate.mean_daily_precipitation * CLIMATE_DAYS_OF_RAIN
    rain = weather.total_precipitation - usual_rain
    dry_air = max(0.0, 40.0 - weather.humidity)

    demand = 1.0
    demand += heat * 0.05
    demand += evaporation * 0.15
    demand += min(0.0, rain) * 0.05
    demand -= max(0.0, rain) * 0.08
    demand += dry_air * 0.01
    demand = max(MIN_DEMAND, min(MAX_DEMAND, demand))

    threshold = round(BASE_MOISTURE_THRESHOLD - (demand - 1.0) * 20)
    threshold = max(
        MIN_MOISTURE_THRESHOLD, min(MAX_MOISTURE_THRESHOLD, threshold)
    )

    interval = round(BASE_ACTIVATION_INTERVAL_MINUTES / demand)
    interval = max(
        MIN_ACTIVATION_INTERVAL_MINUTES,
        min(MAX_ACTIVATION_INTERVAL_MINUTES, interval),
    )

    return PumpParameters(
        active=True,
        moisture_threshold=threshold,
        activation_interval_minutes=interval,
        mode=mode_for_demand(demand),
        reason=describe(weather, climate, demand),
    )


def mode_for_demand(demand: float) -> int:
    """The mode whose amount of water fits the demand.

    The modes give different amounts of water, so a small demand is watered
    with a drip and a big one with the fast mode.
    """
    if demand <= 0.8:
        return MODE_INDEX[PumpModeName.DRIP.name]
    if demand <= 1.2:
        return MODE_INDEX[PumpModeName.SLOW.name]
    return MODE_INDEX[PumpModeName.FAST.name]


def describe(weather: Weather, climate: Climate, demand: float) -> str:
    """The sentence that says why the parameters were changed."""
    usual_rain = climate.mean_daily_precipitation * CLIMATE_DAYS_OF_RAIN
    if demand > 1.05:
        return (
            f"it is {weather.mean_max_temperature:.1f} C against the usual "
            f"{climate.mean_temperature:.1f} C, so the plants need more water"
        )
    if demand < 0.95:
        return (
            f"{weather.total_precipitation:.1f} mm of rain are forecast against "
            f"the usual {usual_rain:.1f} mm, so the plants need less water"
        )
    return "the weather is the usual one, so the parameters stay as they are"


def sanitize(decision: dict) -> PumpParameters | None:
    """The decision of Gemini as safe parameters, or None when it makes no sense.

    The numbers are clamped into their limits, so an answer that asks for
    something impossible cannot be stored.
    """
    threshold = decision.get("moisture_threshold")
    interval = decision.get("activation_interval_minutes")
    mode = decision.get("mode")
    if not isinstance(threshold, int) or not isinstance(interval, int):
        return None

    name = str(mode).upper() if mode is not None else ""
    if name not in gemini_service.CHOICES:
        return None

    reason = decision.get("reason")
    return PumpParameters(
        active=bool(decision.get("activate", True)),
        moisture_threshold=max(
            MIN_MOISTURE_THRESHOLD, min(MAX_MOISTURE_THRESHOLD, threshold)
        ),
        activation_interval_minutes=max(
            MIN_ACTIVATION_INTERVAL_MINUTES,
            min(MAX_ACTIVATION_INTERVAL_MINUTES, interval),
        ),
        mode=MODE_INDEX[PumpModeName[name].name],
        reason=str(reason).strip()[:500] if reason else "",
    )


async def adjust_pump_parameters(db: AsyncSession) -> None:
    """Read the outside conditions and write the parameters of every pump."""
    async with httpx.AsyncClient(timeout=settings.WEATHER_TIMEOUT_SECONDS) as client:
        weather, climate = await weather_service.fetch_conditions(client)

        pumps = await pump_repo.get_all_pumps(db)
        zones = await _zone_states(db, pumps)
        current = await _current_parameters(db)

        decisions: dict[int, dict] = {}
        if gemini_service.gemini_configured():
            try:
                decisions = await gemini_service.decide_parameters(
                    client, weather, climate, zones, current
                )
            except gemini_service.GeminiError as error:
                logger.warning("gemini did not decide: %s", error)
        else:
            logger.info("no GEMINI_API_KEY is set, the rules decide the pumps")

    fallback = compute_parameters(weather, climate)
    modes = {mode.pump_id: mode.mode for mode in await pump_repo.get_all_pump_modes(db)}

    for pump in pumps:
        decision = decisions.get(pump.id)
        parameters = sanitize(decision) if decision else None
        if parameters is None:
            parameters = fallback

        stored = await parameter_repo.get_parameters(db, pump.id)
        if stored and _same_parameters(stored, parameters):
            continue

        await parameter_repo.save_parameters(
            db,
            pump_id=pump.id,
            active=parameters.active,
            moisture_threshold=parameters.moisture_threshold,
            activation_interval_minutes=parameters.activation_interval_minutes,
            mode=parameters.mode,
            reason=parameters.reason,
        )
        logger.info(
            "pump %s was adjusted by %s: %s",
            pump.id,
            "gemini" if decision else "the rules",
            parameters.reason or "no reason given",
        )

        if modes.get(pump.id) != parameters.mode:
            await pump_service.update_pump_mode(db, pump.id, parameters.mode)


async def _zone_states(
    db: AsyncSession, pumps: list
) -> list[ZoneState]:
    """What every zone of the greenhouse looks like right now.

    The readings come from the microcontroller over the WebSocket. The garbled
    ones are left out of the numbers, because their values are made up, but
    the zone is flagged when the latest reading was one of them.
    """
    latest = await sensor_repo.get_latest_reading_per_sensor(db)
    recent = await sensor_repo.get_recent_readings_per_sensor(
        db, RECENT_READING_COUNT
    )
    history = await pump_repo.get_pump_history(db)
    now = datetime.now()

    liters_today: dict[int, float] = {}
    last_watering: dict[int, datetime] = {}
    for entry in history:
        if entry.pump_id is not None:
            liters_today[entry.pump_id] = liters_today.get(entry.pump_id, 0.0) + (
                entry.liters
            )
            if entry.pump_id not in last_watering:
                last_watering[entry.pump_id] = entry.recorded_at

    zones: list[ZoneState] = []
    for pump in pumps:
        zone_readings = recent.get(pump.id, [])
        reading = zone_readings[0] if zone_readings else None
        newest = latest.get(pump.id)
        watered = last_watering.get(pump.id)
        zones.append(
            ZoneState(
                pump_id=pump.id,
                moisture=reading.moisture_level if reading else None,
                humidity=reading.humidity if reading else None,
                temperature=reading.temperature if reading else None,
                minutes_since_last_watering=(
                    (now - watered).total_seconds() / 60 if watered else None
                ),
                liters_today=liters_today.get(pump.id, 0.0),
                # the readings come newest first, the prompt wants them oldest first
                recent_moisture=[
                    entry.moisture_level for entry in reversed(zone_readings)
                ],
                reading_age_minutes=(
                    (now - reading.recorded_at).total_seconds() / 60
                    if reading
                    else None
                ),
                garbled_latest=bool(newest and newest.garbled),
            )
        )
    return zones


async def _current_parameters(db: AsyncSession) -> dict[int, dict]:
    """The parameters the pumps run with right now, to tell Gemini about them."""
    current: dict[int, dict] = {}
    for row in await parameter_repo.get_all_parameters(db):
        current[row.pump_id] = {
            "active": row.active,
            "moisture_threshold": row.moisture_threshold,
            "activation_interval_minutes": row.activation_interval_minutes,
            "mode": mode_name(row.mode),
        }
    return current


def _same_parameters(
    stored, parameters: PumpParameters
) -> bool:
    """Whether the stored parameters are the ones that would be written now."""
    return (
        stored.active == parameters.active
        and stored.moisture_threshold == parameters.moisture_threshold
        and stored.activation_interval_minutes
        == parameters.activation_interval_minutes
        and stored.mode == parameters.mode
    )


async def poll_loop() -> None:
    """Adjust the pumps on a timer, until the task is cancelled."""
    while True:
        try:
            async with AsyncSessionLocal() as db:
                await adjust_pump_parameters(db)
        except asyncio.CancelledError:
            raise
        except weather_service.WeatherSourceError as error:
            logger.warning("the outside conditions are not available: %s", error)
        except Exception:
            logger.exception("the pump adjustment failed")
        await asyncio.sleep(settings.WEATHER_POLL_INTERVAL_SECONDS)
