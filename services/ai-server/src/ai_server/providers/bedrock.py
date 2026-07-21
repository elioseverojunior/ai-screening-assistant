from __future__ import annotations

import time
from base64 import b64encode

import boto3
from botocore.exceptions import ClientError

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider, AnalysisResult

logger = get_logger(__name__)


class BedrockProvider(AnalysisProvider):
    def __init__(self, model: str, settings: Settings) -> None:
        super().__init__(model, settings)
        self.region = settings.bedrock_region
        self.client = boto3.client("bedrock-runtime", region_name=self.region)

    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()

        # Determine image format from bytes
        image_format = self._detect_image_format(image)
        b64_image = b64encode(image).decode()

        conversation = [
            {
                "role": "user",
                "content": [
                    {
                        "image": {
                            "format": image_format,
                            "source": {"bytes": b64_image},
                        }
                    },
                    {"text": prompt},
                ],
            }
        ]

        logger.debug(
            "Calling Bedrock",
            extra={"props": {"model": self.model, "image_size": len(image), "region": self.region}},
        )

        try:
            response = self.client.converse(
                modelId=self.model,
                messages=conversation,
                inferenceConfig={"maxTokens": 2000, "temperature": 0.3},
            )
        except ClientError as e:
            logger.error("Bedrock API error", extra={"props": {"error": str(e), "model": self.model}})
            raise

        elapsed = int((time.monotonic() - start) * 1000)

        reasoning = ""
        response_text = ""
        for item in response["output"]["message"]["content"]:
            for key, value in item.items():
                if key == "reasoningContent":
                    reasoning = value.get("reasoningText", {}).get("text", "")
                elif key == "text":
                    response_text = value

        if reasoning:
            logger.debug("Bedrock reasoning received", extra={"props": {"reasoning_length": len(reasoning)}})

        logger.info(
            "Bedrock analysis completed",
            extra={"props": {"model": self.model, "duration_ms": elapsed, "response_length": len(response_text)}},
        )

        return AnalysisResult(response=response_text, model=self.model, processing_ms=elapsed)

    def _detect_image_format(self, image: bytes) -> str:
        """Detect image format from bytes."""
        if image.startswith(b"\x89PNG\r\n\x1a\n"):
            return "png"
        elif image.startswith(b"\xff\xd8\xff"):
            return "jpeg"
        elif image.startswith(b"GIF87a") or image.startswith(b"GIF89a"):
            return "gif"
        elif image.startswith(b"RIFF") and b"WEBP" in image[:12]:
            return "webp"
        return "png"