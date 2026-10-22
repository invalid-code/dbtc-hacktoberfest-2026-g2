"""Tests for the Gemini service that decides how the pumps behave."""

import httpx
import pytest

from app.services import gemini_service
from app.services.gemini_service import ZoneState
from app.services.weather_service import Climate, Weather


def a_weather() -> Weather:
    return Weather(
        temperature=29.1,
        humidity=74,
        max_temperatures=[33.5, 32.7, 31.9],
        min_temperatures=[25.1, 24.8, 24.2],
        precipitation=[1.6, 0.0, 3.4],
        evaporation=[4.2, 4.0, 3.8],
    )


def a_climate() -> Climate:
    return Climate(
        mean_temperature=28.3,
        mean_daily_precipitation=2.7,
        mean_daily_evaporation=3.4,
        days=65,
    )


def a_zone(pump_id: int = 1) -> ZoneState:
    return ZoneState(
        pump_id=pump_id,
        moisture=22,
        humidity=74,
        temperature=29.1,
        minutes_since_last_watering=40.0,
        liters_today=1.2,
        recent_moisture=[40.0, 33.0, 28.0, 22.0],
        reading_age_minutes=4.0,
    )


def an_answer(decisions: list[dict]) -> dict:
    """The body Gemini answers with."""
    import json

    return {
        "candidates": [
            {"content": {"parts": [{"text": json.dumps(decisions)}]}},
        ]
    }


def a_client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_gemini_is_asked_for_a_json_answer(monkeypatch):
    monkeypatch.setattr(gemini_service.settings, "GEMINI_API_KEY", "the-key")
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["key"] = request.headers.get("x-goog-api-key")
        seen["body"] = request.read().decode()
        return httpx.Response(200, json=an_answer([]))

    async with a_client(handler) as client:
        await gemini_service.decide_parameters(
            client, a_weather(), a_climate(), [a_zone()]
        )

    assert "gemini-3.8-flash:generateContent" in seen["url"]
    assert seen["key"] == "the-key"

    import json

    body = json.loads(seen["body"])
    config = body["generationConfig"]
    assert config["responseMimeType"] == "application/json"
    assert config["responseSchema"]["type"] == "ARRAY"
    assert body["systemInstruction"]["parts"][0]["text"]


async def test_the_facts_are_in_the_prompt():
    prompt = gemini_service.build_prompt(
        a_weather(),
        a_climate(),
        [a_zone()],
        {
            1: {
                "active": True,
                "moisture_threshold": 30,
                "activation_interval_minutes": 60,
                "mode": "FAST",
            }
        },
    )

    assert "33.5 C high" in prompt
    assert "28.3 C on average" in prompt
    assert "22 % soil moisture" in prompt
    assert "1.20 litres used today" in prompt
    assert "waters at 30 % soil moisture" in prompt
    # the readings of the zone and how old they are
    assert "the soil moisture went 40, 33, 28, 22 %" in prompt
    assert "(4 minutes ago)" in prompt


async def test_a_garbled_zone_is_marked_in_the_prompt():
    zone = a_zone()
    garbled = ZoneState(
        pump_id=zone.pump_id,
        moisture=zone.moisture,
        humidity=zone.humidity,
        temperature=zone.temperature,
        minutes_since_last_watering=zone.minutes_since_last_watering,
        liters_today=zone.liters_today,
        recent_moisture=zone.recent_moisture,
        reading_age_minutes=zone.reading_age_minutes,
        garbled_latest=True,
    )

    prompt = gemini_service.build_prompt(a_weather(), a_climate(), [garbled], {})

    assert "the latest reading is garbled" in prompt
    assert "the numbers below are the last real ones" in prompt


async def test_a_zone_without_readings_is_told_in_the_prompt():
    empty = ZoneState(
        pump_id=3,
        moisture=None,
        humidity=None,
        temperature=None,
        minutes_since_last_watering=None,
        liters_today=0.0,
    )

    prompt = gemini_service.build_prompt(a_weather(), a_climate(), [empty], {})

    assert "no soil moisture reading yet" in prompt
    assert "never watered" in prompt


async def test_the_decisions_are_keyed_by_the_pump(monkeypatch):
    monkeypatch.setattr(gemini_service.settings, "GEMINI_API_KEY", "the-key")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=an_answer(
                [
                    {
                        "pump_id": 1,
                        "activate": True,
                        "moisture_threshold": 28,
                        "activation_interval_minutes": 90,
                        "mode": "SLOW",
                        "reason": "the soil is dry and it stays hot",
                    },
                    {
                        "pump_id": 2,
                        "activate": False,
                        "moisture_threshold": 40,
                        "activation_interval_minutes": 120,
                        "mode": "DRIP",
                        "reason": "the soil is wet enough",
                    },
                ]
            ),
        )

    async with a_client(handler) as client:
        decisions = await gemini_service.decide_parameters(
            client, a_weather(), a_climate(), [a_zone()]
        )

    assert set(decisions) == {1, 2}
    assert decisions[1]["mode"] == "SLOW"
    assert decisions[2]["activate"] is False


async def test_without_an_api_key_gemini_is_not_called():
    with pytest.raises(gemini_service.GeminiError):
        async with a_client(lambda request: httpx.Response(200, json={})) as client:
            await gemini_service.decide_parameters(
                client, a_weather(), a_climate(), [a_zone()]
            )


async def test_a_failing_gemini_is_reported(monkeypatch):
    monkeypatch.setattr(gemini_service.settings, "GEMINI_API_KEY", "the-key")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="the api is on fire")

    async with a_client(handler) as client:
        with pytest.raises(gemini_service.GeminiError):
            await gemini_service.decide_parameters(
                client, a_weather(), a_climate(), [a_zone()]
            )


async def test_a_gemini_without_a_candidate_is_reported(monkeypatch):
    monkeypatch.setattr(gemini_service.settings, "GEMINI_API_KEY", "the-key")

    async with a_client(lambda request: httpx.Response(200, json={})) as client:
        with pytest.raises(gemini_service.GeminiError):
            await gemini_service.decide_parameters(
                client, a_weather(), a_climate(), [a_zone()]
            )


async def test_a_gemini_with_a_broken_answer_is_reported(monkeypatch):
    monkeypatch.setattr(gemini_service.settings, "GEMINI_API_KEY", "the-key")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": "not json"}]}}]},
        )

    async with a_client(handler) as client:
        with pytest.raises(gemini_service.GeminiError):
            await gemini_service.decide_parameters(
                client, a_weather(), a_climate(), [a_zone()]
            )
