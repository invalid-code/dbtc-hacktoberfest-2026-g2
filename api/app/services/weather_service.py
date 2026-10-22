"""The outside sources: the weather of the next days and the climate of the last months.

Both come from Open-Meteo (https://open-meteo.com), which needs no api key
and no account:

* the **weather** is the forecast of the next days, from the forecast api,
* the **climate** is the reanalysis of the last months, the seasonal normal
  of the place the greenhouse stands in, from the same api with a window of
  past days.

The two are asked for separately because they say different things: the
forecast says what the next days will be like, the climate says what they
usually are like, and the difference between the two is what the pumps are
adjusted by.
"""

import logging

from dataclasses import dataclass

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

WEATHER_API_URL = "https://api.open-meteo.com/v1/forecast"
CLIMATE_API_URL = "https://api.open-meteo.com/v1/forecast"

WEATHER_CURRENT_VARIABLES = "temperature_2m,relative_humidity_2m,precipitation"
WEATHER_DAILY_VARIABLES = (
    "precipitation_sum,temperature_2m_max,temperature_2m_min,"
    "et0_fao_evapotranspiration"
)
CLIMATE_DAILY_VARIABLES = (
    "temperature_2m_mean,precipitation_sum,et0_fao_evapotranspiration"
)

# How many days ahead the weather is asked for.
FORECAST_DAYS = 3


class WeatherSourceError(Exception):
    """The outside source could not be read or did not answer what was asked for."""


@dataclass(frozen=True)
class Weather:
    """The weather of the greenhouse for the next days."""

    temperature: float
    humidity: float
    max_temperatures: list[float]
    min_temperatures: list[float]
    precipitation: list[float]
    evaporation: list[float]

    @property
    def mean_max_temperature(self) -> float:
        """The mean of the highest temperature of every forecast day."""
        return _mean(self.max_temperatures)

    @property
    def mean_temperature(self) -> float:
        """The mean of the daily middle between the lowest and the highest."""
        return _mean(
            [
                (high + low) / 2
                for high, low in zip(self.max_temperatures, self.min_temperatures)
            ]
        )

    @property
    def total_precipitation(self) -> float:
        """The rain of all the forecast days together, in mm."""
        return sum(self.precipitation)

    @property
    def mean_evaporation(self) -> float:
        """The mean evaporation of a forecast day, in mm."""
        return _mean(self.evaporation)


@dataclass(frozen=True)
class Climate:
    """The climate of the place, the normal of the last months."""

    mean_temperature: float
    mean_daily_precipitation: float
    mean_daily_evaporation: float
    days: int


def _mean(values: list[float]) -> float:
    """The mean of the values, zero when there are none."""
    return sum(values) / len(values) if values else 0.0


def _daily_values(payload: dict, key: str) -> list[float]:
    """The values of one daily variable, the days without a value left out."""
    daily = payload.get("daily") or {}
    values = daily.get(key) or []
    return [float(value) for value in values if value is not None]


async def fetch_weather(client: httpx.AsyncClient) -> Weather:
    """Read the forecast of the next days for the place of the greenhouse."""
    params = {
        "latitude": settings.WEATHER_LATITUDE,
        "longitude": settings.WEATHER_LONGITUDE,
        "current": WEATHER_CURRENT_VARIABLES,
        "daily": WEATHER_DAILY_VARIABLES,
        "forecast_days": FORECAST_DAYS,
        "timezone": "auto",
    }

    payload = await _get(client, WEATHER_API_URL, params)

    current = payload.get("current") or {}
    if "temperature_2m" not in current:
        raise WeatherSourceError("the forecast came without a current temperature")

    return Weather(
        temperature=float(current["temperature_2m"]),
        humidity=float(current.get("relative_humidity_2m") or 0.0),
        max_temperatures=_daily_values(payload, "temperature_2m_max"),
        min_temperatures=_daily_values(payload, "temperature_2m_min"),
        precipitation=_daily_values(payload, "precipitation_sum"),
        evaporation=_daily_values(payload, "et0_fao_evapotranspiration"),
    )


async def fetch_climate(client: httpx.AsyncClient) -> Climate:
    """Read the seasonal normal of the place of the greenhouse."""
    params = {
        "latitude": settings.WEATHER_LATITUDE,
        "longitude": settings.WEATHER_LONGITUDE,
        "past_days": settings.WEATHER_CLIMATE_PAST_DAYS,
        "forecast_days": 1,
        "daily": CLIMATE_DAILY_VARIABLES,
        "timezone": "auto",
    }

    payload = await _get(client, CLIMATE_API_URL, params)

    temperatures = _daily_values(payload, "temperature_2m_mean")
    if not temperatures:
        raise WeatherSourceError("the climate came without any temperature")

    return Climate(
        mean_temperature=_mean(temperatures),
        mean_daily_precipitation=_mean(
            _daily_values(payload, "precipitation_sum")
        ),
        mean_daily_evaporation=_mean(
            _daily_values(payload, "et0_fao_evapotranspiration")
        ),
        days=len(temperatures),
    )


async def fetch_conditions(client: httpx.AsyncClient) -> tuple[Weather, Climate]:
    """Read the weather and the climate of the greenhouse in one go."""
    weather = await fetch_weather(client)
    climate = await fetch_climate(client)
    logger.info(
        "the weather is %.1f C and %.1f mm of rain are forecast, the climate "
        "averages %.1f C",
        weather.temperature,
        weather.total_precipitation,
        climate.mean_temperature,
    )
    return weather, climate


async def _get(
    client: httpx.AsyncClient,
    url: str,
    params: dict[str, object],
) -> dict:
    """Ask an outside source for its json and make sure it answered."""
    try:
        response = await client.get(url, params=params)
        response.raise_for_status()
        payload = response.json()
    except httpx.HTTPError as error:
        raise WeatherSourceError(f"{url} could not be read: {error}") from error
    except ValueError as error:
        raise WeatherSourceError(f"{url} did not answer with json") from error

    if not isinstance(payload, dict) or payload.get("error"):
        reason = payload.get("reason") if isinstance(payload, dict) else payload
        raise WeatherSourceError(f"{url} refused the request: {reason}")

    return payload
