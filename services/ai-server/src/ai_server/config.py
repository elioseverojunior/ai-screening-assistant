from __future__ import annotations

from os import environ
from pathlib import Path
from typing import Literal

from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
    TomlConfigSettingsSource,
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        env_prefix="AI_SERVER_",
        extra="ignore",
    )

    host: str = "0.0.0.0"
    port: int = 8000
    metrics_port: int = 0
    health_port: int = 8001

    cb_failure_threshold: int = 5
    cb_recovery_timeout: int = 30

    default_model: str = "nvidia.nemotron-nano-12b-v2"
    provider: Literal["ollama", "huggingface", "groq", "gemini", "cloudflare", "zen", "bedrock"] = "bedrock"

    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = ""

    huggingface_api_token: str = ""
    huggingface_model: str = ""

    groq_api_key: str = ""
    groq_model: str = ""

    gemini_api_key: str = ""
    gemini_model: str = ""

    cloudflare_api_token: str = ""
    cloudflare_account_id: str = ""
    cloudflare_model: str = ""

    zen_api_key: str = ""
    zen_model: str = ""

    bedrock_region: str = "us-east-1"
    bedrock_model: str = ""
    bedrock_profile: str = "default"
    bedrock_use_mantle: bool = False
    mantle_api_endpoint: str = ""
    mantle_api_key: str = ""

    log_level: str = "INFO"

    otel_collector_endpoint: str = ""
    otel_log_level: str = "INFO"
    otel_metrics_prefix: str = "ai_screening"

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        toml_files: list[str] = ["configs/config.toml"]
        env = environ.get("AI_SERVER_ENVIROMENT", "")
        if env:
            toml_files.append(f"configs/config.{env}.toml")
        toml_source = TomlConfigSettingsSource(settings_cls, toml_file=toml_files)
        return (
            init_settings,
            env_settings,
            dotenv_settings,
            toml_source,
            file_secret_settings,
        )

    def resolve_model(self) -> str:
        provider_key = f"{self.provider}_model"
        custom_model = getattr(self, provider_key, "")
        return custom_model or self.default_model

    @classmethod
    def from_env_file(cls, path: str | Path | None = None) -> Settings:
        return cls(_env_file=path)  # type: ignore[call-arg]


def get_settings() -> Settings:
    return Settings()
