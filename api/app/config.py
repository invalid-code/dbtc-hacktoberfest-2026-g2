"""Application settings, read by pydantic-settings from the environment and the git-ignored .env."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Every field is an environment variable of the same name.

    FRONTEND_URL is the CORS allow-list, an empty DEVICE_URL disables device
    polling, and an empty GEMINI_API_KEY makes the gemini endpoints return 503.
    """
    DB_CONN_STR: str
    FRONTEND_URL: str = "*"
    DEVICE_URL: str = ""
    DEVICE_POLL_INTERVAL_SECONDS: float = 5.0
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-3.8-flash"
    GEMINI_TIMEOUT_SECONDS: float = 30.0

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
