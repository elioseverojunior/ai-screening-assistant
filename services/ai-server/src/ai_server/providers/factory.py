from __future__ import annotations

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider
from ai_server.providers.bedrock import BedrockProvider
from ai_server.providers.mantle import MantleProvider
from ai_server.providers.ollama import OllamaProvider
from ai_server.providers.zen import ZenProvider

logger = get_logger(__name__)


def create_provider(settings: Settings) -> AnalysisProvider:
    model = settings.resolve_model()
    match settings.provider:
        case "bedrock":
            if settings.bedrock_use_mantle:
                logger.debug("Creating Mantle provider", extra={"props": {"model": model, "endpoint": settings.mantle_api_endpoint}})
                return MantleProvider(model=model, settings=settings)
            logger.debug("Creating Bedrock provider", extra={"props": {"model": model, "region": settings.bedrock_region}})
            return BedrockProvider(model=model, settings=settings)
        case "ollama":
            logger.debug("Creating Ollama provider", extra={"props": {"model": model}})
            return OllamaProvider(model=model, settings=settings)
        case "zen":
            logger.debug("Creating Zen provider", extra={"props": {"model": model}})
            return ZenProvider(model=model, settings=settings)
        case _:
            logger.warning("Unknown provider %s, falling back to Bedrock", settings.provider)
            return BedrockProvider(model=model, settings=settings)
