"""Application settings, read by pydantic-settings from the environment and the git-ignored .env."""

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Every field is an environment variable of the same name.

    FRONTEND_URL is the CORS allow-list and WEATHER_ENABLED turns the automatic
    pump adjustment off. An empty GEMINI_API_KEY leaves the rules in charge of
    the pumps instead of Gemini.
    """
    DB_CONN_STR: str
    FRONTEND_URL: str = "*"
    WEATHER_ENABLED: bool = True
    WEATHER_LATITUDE: float = 14.5995
    WEATHER_LONGITUDE: float = 120.9842
    WEATHER_POLL_INTERVAL_SECONDS: float = 3600.0
    WEATHER_TIMEOUT_SECONDS: float = 30.0
    WEATHER_CLIMATE_PAST_DAYS: int = 92
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-3.8-flash"
    GEMINI_TIMEOUT_SECONDS: float = 30.0
    LOG_LEVEL: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    LOG_FORMAT: Literal["text", "json"] = "text"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
