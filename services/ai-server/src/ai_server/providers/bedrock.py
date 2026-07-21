from __future__ import annotations

import time
from base64 import b64encode

import boto3
import httpx
from botocore.exceptions import ClientError
from botocore.config import Config

from ai_server.config import Settings
from ai_server.logging import get_logger
from ai_server.providers.base import AnalysisProvider, AnalysisResult

logger = get_logger(__name__)


class BedrockProvider(AnalysisProvider):
    def __init__(self, model: str, settings: Settings) -> None:
        super().__init__(model, settings)
        self.region = settings.bedrock_region
        self.profile = settings.bedrock_profile
        self.use_mantle = settings.bedrock_use_mantle
        self.mantle_endpoint = settings.mantle_api_endpoint
        self.mantle_key = settings.mantle_api_key

        if self.use_mantle:
            if not self.mantle_endpoint:
                raise ValueError("Mantle API endpoint required when bedrock_use_mantle=true")
            self._http = httpx.AsyncClient(
                base_url=self.mantle_endpoint,
                timeout=60.0,
                headers={"Authorization": f"Bearer {self.mantle_key}"} if self.mantle_key else None,
            )
        else:
            session = boto3.Session(profile_name=self.profile) if self.profile else boto3.Session()
            self.client = session.client("bedrock-runtime", region_name=self.region)

    async def analyze(self, image: bytes, prompt: str) -> AnalysisResult:
        if self.use_mantle:
            return await self._analyze_mantle(image, prompt)
        return await self._analyze_bedrock(image, prompt)

    async def _analyze_bedrock(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()

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

    async def _analyze_mantle(self, image: bytes, prompt: str) -> AnalysisResult:
        start = time.monotonic()

        image_format = self._detect_image_format(image)
        b64_image = b64encode(image).decode()

        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": f"data:image/{image_format};base64,{b64_image}"},
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
            "max_tokens": 2000,
            "temperature": 0.3,
        }

        logger.debug(
            "Calling Mantle API (Bedrock proxy)",
            extra={"props": {"model": self.model, "image_size": len(image), "endpoint": self.mantle_endpoint}},
        )

        try:
            response = await self._http.post("/v1/chat/completions", json=payload)
            response.raise_for_status()
            data = response.json()
        except httpx.HTTPError as e:
            logger.error("Mantle API error", extra={"props": {"error": str(e), "model": self.model}})
            raise

        elapsed = int((time.monotonic() - start) * 1000)

        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")

        logger.info(
            "Mantle (Bedrock) analysis completed",
            extra={"props": {"model": self.model, "duration_ms": elapsed, "response_length": len(content)}},
        )

        return AnalysisResult(response=content, model=self.model, processing_ms=elapsed)

    async def close(self) -> None:
        if self.use_mantle:
            await self._http.aclose()

    def _detect_image_format(self, image: bytes) -> str:
        if image.startswith(b"\x89PNG\r\n\x1a\n"):
            return "png"
        elif image.startswith(b"\xff\xd8\xff"):
            return "jpeg"
        elif image.startswith(b"GIF87a") or image.startswith(b"GIF89a"):
            return "gif"
        elif image.startswith(b"RIFF") and b"WEBP" in image[:12]:
            return "webp"
        return "png"