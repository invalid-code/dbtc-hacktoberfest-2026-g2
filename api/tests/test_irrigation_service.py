"""Tests for the automatic adjustment of the pump activation parameters."""

from datetime import datetime, timedelta

import pytest

from app.modes import MODE_INDEX, PumpModeName
from app.repositories import parameter_repo, pump_repo, sensor_repo
from app.services import irrigation_service, pump_service
from app.services.weather_service import Climate, Weather


def a_weather(
    temperature: float = 15.0,
    humidity: float = 60.0,
    max_temperatures: list[float] | None = None,
    precipitation: list[float] | None = None,
    evaporation: list[float] | None = None,
) -> Weather:
    """The weather of a few days, the usual one unless it is said otherwise."""
    return Weather(
        temperature=temperature,
        humidity=humidity,
        max_temperatures=max_temperatures or [15.0, 15.0, 15.0],
        min_temperatures=[10.0, 10.0, 10.0],
        precipitation=precipitation or [2.0, 2.0, 2.0],
        evaporation=evaporation or [1.0, 1.0, 1.0],
    )


def a_climate(
    mean_temperature: float = 15.0,
    mean_daily_precipitation: float = 2.0,
    mean_daily_evaporation: float = 1.0,
) -> Climate:
    """The usual weather of the place."""
    return Climate(
        mean_temperature=mean_temperature,
        mean_daily_precipitation=mean_daily_precipitation,
        mean_daily_evaporation=mean_daily_evaporation,
        days=92,
    )


def test_the_usual_weather_keeps_the_usual_parameters():
    parameters = irrigation_service.compute_parameters(a_weather(), a_climate())

    assert parameters.moisture_threshold == 30
    assert parameters.activation_interval_minutes == 60
    assert parameters.mode == MODE_INDEX[PumpModeName.SLOW.name]


def test_a_hot_and_dry_forecast_asks_for_more_water():
    weather = a_weather(
        max_temperatures=[32.0, 33.0, 31.0],
        precipitation=[0.0, 0.0, 0.0],
        evaporation=[5.0, 5.0, 5.0],
    )

    parameters = irrigation_service.compute_parameters(weather, a_climate())

    assert parameters.moisture_threshold < 30
    assert parameters.activation_interval_minutes < 60
    assert parameters.mode == MODE_INDEX[PumpModeName.FAST.name]
    assert "need more water" in parameters.reason


def test_a_rainy_forecast_asks_for_less_water():
    weather = a_weather(
        max_temperatures=[10.0, 10.0, 10.0],
        precipitation=[20.0, 15.0, 10.0],
        evaporation=[0.3, 0.3, 0.3],
    )

    parameters = irrigation_service.compute_parameters(weather, a_climate())

    assert parameters.moisture_threshold > 30
    assert parameters.activation_interval_minutes > 60
    assert parameters.mode == MODE_INDEX[PumpModeName.DRIP.name]
    assert "need less water" in parameters.reason


def test_the_parameters_stay_inside_their_limits():
    weather = a_weather(
        max_temperatures=[60.0, 60.0, 60.0],
        precipitation=[0.0, 0.0, 0.0],
        evaporation=[20.0, 20.0, 20.0],
    )

    parameters = irrigation_service.compute_parameters(weather, a_climate())

    assert (
        irrigation_service.MIN_MOISTURE_THRESHOLD
        <= parameters.moisture_threshold
        <= irrigation_service.MAX_MOISTURE_THRESHOLD
    )
    assert (
        irrigation_service.MIN_ACTIVATION_INTERVAL_MINUTES
        <= parameters.activation_interval_minutes
        <= irrigation_service.MAX_ACTIVATION_INTERVAL_MINUTES
    )


def test_the_parameters_stay_inside_their_limits_the_other_way():
    weather = a_weather(
        max_temperatures=[-20.0, -20.0, -20.0],
        precipitation=[100.0, 100.0, 100.0],
        evaporation=[0.0, 0.0, 0.0],
    )

    parameters = irrigation_service.compute_parameters(weather, a_climate())

    assert (
        irrigation_service.MIN_MOISTURE_THRESHOLD
        <= parameters.moisture_threshold
        <= irrigation_service.MAX_MOISTURE_THRESHOLD
    )
    assert (
        irrigation_service.MIN_ACTIVATION_INTERVAL_MINUTES
        <= parameters.activation_interval_minutes
        <= irrigation_service.MAX_ACTIVATION_INTERVAL_MINUTES
    )


def test_a_strange_day_cannot_move_the_parameters_too_far():
    weather = a_weather(
        max_temperatures=[60.0, 60.0, 60.0],
        precipitation=[0.0, 0.0, 0.0],
        evaporation=[20.0, 20.0, 20.0],
    )

    parameters = irrigation_service.compute_parameters(weather, a_climate())

    assert parameters.moisture_threshold == irrigation_service.MIN_MOISTURE_THRESHOLD


def test_the_mode_follows_the_demand():
    assert (
        irrigation_service.mode_for_demand(0.5)
        == MODE_INDEX[PumpModeName.DRIP.name]
    )
    assert (
        irrigation_service.mode_for_demand(1.0)
        == MODE_INDEX[PumpModeName.SLOW.name]
    )
    assert (
        irrigation_service.mode_for_demand(2.0)
        == MODE_INDEX[PumpModeName.FAST.name]
    )


async def test_the_parameters_are_written_for_every_pump(db_session, monkeypatch):
    weather = a_weather(max_temperatures=[32.0, 33.0, 31.0])

    async def fake_conditions(client):
        return weather, a_climate()

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    for pump in await pump_repo.get_all_pumps(db_session):
        stored = await parameter_repo.get_parameters(db_session, pump.id)
        assert stored is not None
        assert stored.moisture_threshold < 30
        assert stored.mode == MODE_INDEX[PumpModeName.FAST.name]
        assert stored.reason


async def test_the_mode_of_the_pump_follows_the_weather(db_session, monkeypatch):
    weather = a_weather(max_temperatures=[32.0, 33.0, 31.0])

    async def fake_conditions(client):
        return weather, a_climate()

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    modes = await pump_service.get_pump_modes(db_session)
    assert {mode.mode for mode in modes} == {MODE_INDEX[PumpModeName.FAST.name]}


async def test_unchanged_parameters_are_not_written_again(db_session, monkeypatch):
    weather = a_weather()

    async def fake_conditions(client):
        return weather, a_climate()

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )

    await irrigation_service.adjust_pump_parameters(db_session)
    first = await parameter_repo.get_parameters(db_session, 1)

    await irrigation_service.adjust_pump_parameters(db_session)
    second = await parameter_repo.get_parameters(db_session, 1)

    assert first.updated_at == second.updated_at


async def test_the_parameters_are_listed(client, db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    response = await client.get("/pump/parameters/")

    assert response.status_code == 200
    parameters = response.json()
    assert len(parameters) == 3
    assert {parameter["pump_id"] for parameter in parameters} == {1, 2, 3}
    assert parameters[0]["active"] is True
    assert parameters[0]["moisture_threshold"] == 30
    assert parameters[0]["activation_interval_minutes"] == 60
    assert parameters[0]["mode_liters_per_second"] > 0
    assert parameters[0]["updated_at"]


def a_decision(pump_id: int = 1, **overrides) -> dict:
    """A decision as Gemini would answer it."""
    decision = {
        "pump_id": pump_id,
        "activate": True,
        "moisture_threshold": 28,
        "activation_interval_minutes": 90,
        "mode": "SLOW",
        "reason": "the soil is dry and it stays hot",
    }
    decision.update(overrides)
    return decision


def test_a_decision_of_gemini_becomes_the_parameters():
    parameters = irrigation_service.sanitize(a_decision())

    assert parameters is not None
    assert parameters.active is True
    assert parameters.moisture_threshold == 28
    assert parameters.activation_interval_minutes == 90
    assert parameters.mode == MODE_INDEX[PumpModeName.SLOW.name]
    assert parameters.reason == "the soil is dry and it stays hot"


def test_a_decision_of_gemini_cannot_leave_the_limits():
    parameters = irrigation_service.sanitize(
        a_decision(
            moisture_threshold=9999,
            activation_interval_minutes=1,
        )
    )

    assert parameters is not None
    assert parameters.moisture_threshold == irrigation_service.MAX_MOISTURE_THRESHOLD
    assert (
        parameters.activation_interval_minutes
        == irrigation_service.MIN_ACTIVATION_INTERVAL_MINUTES
    )


def test_a_decision_that_makes_no_sense_is_thrown_away():
    assert irrigation_service.sanitize(a_decision(mode="SPRINKLE")) is None
    assert irrigation_service.sanitize(a_decision(mode="BLENDER")) is None
    assert irrigation_service.sanitize(a_decision(moisture_threshold="low")) is None
    assert irrigation_service.sanitize({"pump_id": 1}) is None


def test_gemini_can_stop_a_pump_from_watering():
    parameters = irrigation_service.sanitize(a_decision(activate=False))

    assert parameters is not None
    assert parameters.active is False


async def test_gemini_decides_the_parameters(db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        return {zone.pump_id: a_decision(zone.pump_id) for zone in zones}

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    stored = await parameter_repo.get_parameters(db_session, 1)
    assert stored.moisture_threshold == 28
    assert stored.activation_interval_minutes == 90
    assert stored.mode == MODE_INDEX[PumpModeName.SLOW.name]
    assert stored.reason == "the soil is dry and it stays hot"


async def test_gemini_can_stop_a_pump_from_watering_at_all(db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        return {
            zone.pump_id: a_decision(zone.pump_id, activate=False)
            for zone in zones
        }

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    stored = await parameter_repo.get_parameters(db_session, 1)
    assert stored.active is False


async def test_the_rules_decide_when_gemini_is_not_there(db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: False
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    stored = await parameter_repo.get_parameters(db_session, 1)
    assert stored.moisture_threshold == 30
    assert stored.activation_interval_minutes == 60


async def test_the_rules_decide_when_gemini_fails(db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def failing_decisions(client, weather, climate, zones, current=None):
        raise irrigation_service.gemini_service.GeminiError("no answer")

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", failing_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    stored = await parameter_repo.get_parameters(db_session, 1)
    assert stored.moisture_threshold == 30
    assert stored.reason


async def test_the_rules_decide_for_the_pumps_gemini_forgot(db_session, monkeypatch):
    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        return {1: a_decision(1)}

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    first = await parameter_repo.get_parameters(db_session, 1)
    second = await parameter_repo.get_parameters(db_session, 2)

    assert first.moisture_threshold == 28
    assert second.moisture_threshold == 30


async def test_gemini_sees_the_readings_of_the_microcontroller(
    db_session, monkeypatch
):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=40,
        humidity=70,
        recorded_at=datetime.now() - timedelta(minutes=3),
        temperature=28.0,
    )
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=35,
        humidity=72,
        recorded_at=datetime.now() - timedelta(minutes=2),
        temperature=28.5,
    )

    seen: dict = {}

    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        seen["zones"] = zones
        return {}

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    zone = next(zone for zone in seen["zones"] if zone.pump_id == 1)
    assert zone.moisture == 35
    assert zone.humidity == 72
    assert zone.temperature == 28.5
    # the readings of the zone, oldest first
    assert zone.recent_moisture == [40, 35]
    assert zone.reading_age_minutes is not None
    assert zone.garbled_latest is False


async def test_the_garbled_readings_are_left_out(db_session, monkeypatch):
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=35,
        humidity=72,
        recorded_at=datetime.now() - timedelta(minutes=2),
        temperature=28.5,
    )
    # the newest reading of the zone is one of the haunted ones
    await sensor_repo.create_sensor_data(
        db=db_session,
        sensor_id=1,
        moisture_level=666,
        humidity=999,
        recorded_at=datetime.now(),
        temperature=-42.5,
        garbled=True,
    )

    seen: dict = {}

    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        seen["zones"] = zones
        return {}

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    zone = next(zone for zone in seen["zones"] if zone.pump_id == 1)
    # the numbers are the last real ones
    assert zone.moisture == 35
    assert zone.recent_moisture == [35]
    # but the zone is marked as garbled
    assert zone.garbled_latest is True


async def test_a_zone_without_readings_is_told(db_session, monkeypatch):
    seen: dict = {}

    async def fake_conditions(client):
        return a_weather(), a_climate()

    async def fake_decisions(client, weather, climate, zones, current=None):
        seen["zones"] = zones
        return {}

    monkeypatch.setattr(
        irrigation_service.weather_service, "fetch_conditions", fake_conditions
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "gemini_configured", lambda: True
    )
    monkeypatch.setattr(
        irrigation_service.gemini_service, "decide_parameters", fake_decisions
    )

    await irrigation_service.adjust_pump_parameters(db_session)

    zone = next(zone for zone in seen["zones"] if zone.pump_id == 2)
    assert zone.moisture is None
    assert zone.recent_moisture == []
    assert zone.reading_age_minutes is None
    assert zone.garbled_latest is False
