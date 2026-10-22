"""Tests for the outside weather and climate sources."""

import httpx
import pytest

from app.services import weather_service

WEATHER_PAYLOAD = {
    "latitude": 52.5,
    "longitude": 13.4,
    "timezone": "Europe/Berlin",
    "current": {
        "time": "2026-10-22T13:30",
        "temperature_2m": 12.8,
        "relative_humidity_2m": 60,
        "precipitation": 0.0,
    },
    "daily": {
        "time": ["2026-10-22", "2026-10-23", "2026-10-24"],
        "precipitation_sum": [4.1, 1.4, 7.06],
        "temperature_2m_max": [13.4, 13.6, 11.5],
        "temperature_2m_min": [9.8, 6.2, 7.6],
        "et0_fao_evapotranspiration": [1.49, 1.18, 1.11],
    },
}

CLIMATE_PAYLOAD = {
    "daily": {
        "time": ["2026-08-01", "2026-08-02", "2026-08-03"],
        # the first days of the reanalysis are not ready yet
        "temperature_2m_mean": [None, 17.1, 18.1],
        "precipitation_sum": [None, 0.2, 6.1],
        "et0_fao_evapotranspiration": [None, 2.61, 1.28],
    },
}


def a_client(handler) -> httpx.AsyncClient:
    """A client that answers with whatever the handler says."""
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_the_forecast_is_read():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=WEATHER_PAYLOAD)

    async with a_client(handler) as client:
        weather = await weather_service.fetch_weather(client)

    assert weather.temperature == 12.8
    assert weather.humidity == 60
    assert weather.max_temperatures == [13.4, 13.6, 11.5]
    assert weather.mean_max_temperature == pytest.approx(12.8333, abs=0.001)
    assert weather.total_precipitation == pytest.approx(12.56, abs=0.001)
    assert weather.mean_evaporation == pytest.approx(1.26, abs=0.001)


async def test_the_forecast_asks_for_the_place_of_the_greenhouse():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["latitude"] != ""
        assert request.url.params["forecast_days"] == "3"
        assert "temperature_2m_max" in request.url.params["daily"]
        return httpx.Response(200, json=WEATHER_PAYLOAD)

    async with a_client(handler) as client:
        await weather_service.fetch_weather(client)


async def test_the_climate_is_read():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=CLIMATE_PAYLOAD)

    async with a_client(handler) as client:
        climate = await weather_service.fetch_climate(client)

    assert climate.mean_temperature == pytest.approx(17.6, abs=0.001)
    assert climate.mean_daily_precipitation == pytest.approx(3.15, abs=0.001)
    assert climate.mean_daily_evaporation == pytest.approx(1.945, abs=0.001)
    assert climate.days == 2


async def test_the_climate_asks_for_the_past_months():
    def handler(request: httpx.Request) -> httpx.Response:
        assert int(request.url.params["past_days"]) > 30
        return httpx.Response(200, json=CLIMATE_PAYLOAD)

    async with a_client(handler) as client:
        await weather_service.fetch_climate(client)


async def test_a_source_that_fails_is_reported():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="the source is down")

    async with a_client(handler) as client:
        with pytest.raises(weather_service.WeatherSourceError):
            await weather_service.fetch_weather(client)


async def test_a_source_that_refuses_is_reported():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"error": True, "reason": "no such place"})

    async with a_client(handler) as client:
        with pytest.raises(weather_service.WeatherSourceError):
            await weather_service.fetch_climate(client)


async def test_a_source_that_answers_nonsense_is_reported():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="not json at all")

    async with a_client(handler) as client:
        with pytest.raises(weather_service.WeatherSourceError):
            await weather_service.fetch_weather(client)


async def test_a_forecast_without_a_temperature_is_reported():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"current": {}, "daily": {}})

    async with a_client(handler) as client:
        with pytest.raises(weather_service.WeatherSourceError):
            await weather_service.fetch_weather(client)


async def test_a_climate_without_a_temperature_is_reported():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"daily": {"temperature_2m_mean": [None]}})

    async with a_client(handler) as client:
        with pytest.raises(weather_service.WeatherSourceError):
            await weather_service.fetch_climate(client)
