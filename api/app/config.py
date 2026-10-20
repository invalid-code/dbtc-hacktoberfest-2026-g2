from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DB_CONN_STR: str
    FRONTEND_URL: str = "*"
    SIMULATE_SENSORS: bool = False
    SIMULATE_INTERVAL_SECONDS: float = 5.0

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
