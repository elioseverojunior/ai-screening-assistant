from __future__ import annotations

from unittest.mock import MagicMock, patch

import httpx
import pytest
from botocore.exceptions import ClientError

from ai_server.config import Settings
from ai_server.providers import AnalysisProvider, AnalysisResult, create_provider
from ai_server.providers.bedrock import BedrockProvider
from ai_server.providers.ollama import OllamaProvider
from ai_server.providers.zen import ZenProvider


def _make_response(
    status: int,
    content: str = "",
) -> httpx.Response:
    req = httpx.Request("POST", "http://localhost:11434/api/chat")
    return httpx.Response(status, json={"message": {"role": "assistant", "content": content}}, request=req)


def _make_zen_response(
    status: int,
    json_data: dict | None = None,
) -> httpx.Response:
    req = httpx.Request("POST", "https://opencode.ai/zen/v1/chat/completions")
    return httpx.Response(status, json=json_data, request=req)


def _make_bedrock_response(content: str, reasoning: str = "") -> dict:
    """Create a mock Bedrock converse response."""
    response = {
        "output": {
            "message": {
                "content": [{"text": content}]
            }
        }
    }
    if reasoning:
        response["output"]["message"]["content"].insert(0, {
            "reasoningContent": {"reasoningText": {"text": reasoning}}
        })
    return response


class TestAnalysisResult:
    def test_dataclass_fields(self) -> None:
        result = AnalysisResult(response="test", model="m", processing_ms=100)
        assert result.response == "test"
        assert result.model == "m"
        assert result.processing_ms == 100


class TestAnalysisProviderBase:
    def test_abstract_cannot_instantiate(self) -> None:
        with pytest.raises(TypeError, match="Can't instantiate abstract class"):
            AnalysisProvider(model="m", settings=object())  # type: ignore[abstract]


class TestCreateProvider:
    def test_returns_ollama_provider_by_default(self) -> None:
        settings = Settings(provider="ollama")
        provider = create_provider(settings)
        assert isinstance(provider, AnalysisProvider)
        assert provider.model == "llama3.2-vision"

    def test_ollama_provider_uses_custom_model(self) -> None:
        settings = Settings(provider="ollama", ollama_model="llama3.2-vision")
        provider = create_provider(settings)
        assert provider.model == "llama3.2-vision"

    def test_fallback_to_bedrock_for_unsupported_provider(self) -> None:
        settings = Settings(provider="huggingface")
        provider = create_provider(settings)
        assert isinstance(provider, AnalysisProvider)
        assert isinstance(provider, BedrockProvider)

    def test_fallback_uses_correct_model(self) -> None:
        settings = Settings(
            provider="huggingface", default_model="fallback-model"
        )
        provider = create_provider(settings)
        assert provider.model == "fallback-model"

    def test_zen_provider_returns_zen_provider(self) -> None:
        settings = Settings(provider="zen", zen_model="deepseek-v4-flash-free", zen_api_key="test-key")
        provider = create_provider(settings)
        assert isinstance(provider, AnalysisProvider)
        assert isinstance(provider, ZenProvider)

    def test_zen_provider_uses_custom_model(self) -> None:
        settings = Settings(provider="zen", zen_model="custom-model", zen_api_key="test-key")
        provider = create_provider(settings)
        assert provider.model == "custom-model"

    def test_zen_provider_requires_api_key(self) -> None:
        settings = Settings(provider="zen", zen_api_key="")
        with pytest.raises(ValueError, match="zen_api_key is required"):
            create_provider(settings)

    def test_bedrock_provider_returns_bedrock_provider(self) -> None:
        settings = Settings(provider="bedrock", default_model="bedrock-model", bedrock_region="us-east-1")
        provider = create_provider(settings)
        assert isinstance(provider, AnalysisProvider)
        assert isinstance(provider, BedrockProvider)

    def test_bedrock_provider_uses_custom_model(self) -> None:
        settings = Settings(provider="bedrock", bedrock_model="custom-bedrock-model", bedrock_region="us-east-1")
        provider = create_provider(settings)
        assert provider.model == "custom-bedrock-model"


class TestOllamaProvider:
    @pytest.fixture
    def settings(self) -> Settings:
        return Settings()

    @pytest.fixture
    def provider(self, settings: Settings) -> AnalysisProvider:
        return create_provider(settings)

    async def test_analyze_returns_result(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_response(200, content="I see a red square.")

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.response == "I see a red square."
            assert result.model == "llama3.2-vision"
            assert result.processing_ms >= 0

            mock_post.assert_called_once()
            call_kwargs = mock_post.call_args[1]
            assert call_kwargs["json"]["model"] == "llama3.2-vision"
            assert call_kwargs["json"]["messages"][0]["role"] == "user"
            assert call_kwargs["json"]["messages"][0]["content"] == "Describe"
            assert "images" in call_kwargs["json"]["messages"][0]

    async def test_analyze_with_custom_model(self, settings: Settings) -> None:
        settings.ollama_model = "custom-vision-model"
        provider = create_provider(settings)
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_response(200, content="Analysis complete.")

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.model == "custom-vision-model"

    async def test_raises_on_http_error(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_response(500, content="")

            with pytest.raises(httpx.HTTPStatusError):
                await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

    async def test_sends_base64_image(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_response(200, content="ok")

            await provider.analyze(image=b"\x89PNG\r\n\x1a\n", prompt="X")

            call_kwargs = mock_post.call_args[1]
            image_b64 = call_kwargs["json"]["messages"][0]["images"][0]
            from base64 import b64decode

            decoded = b64decode(image_b64)
            assert decoded == b"\x89PNG\r\n\x1a\n"


class TestZenProvider:
    @pytest.fixture
    def settings(self) -> Settings:
        return Settings(provider="zen", zen_api_key="test-key-123", default_model="deepseek-v4-flash-free")

    @pytest.fixture
    def provider(self, settings: Settings) -> AnalysisProvider:
        return create_provider(settings)

    async def test_analyze_returns_result(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(
                200, {"choices": [{"message": {"content": "I see a red square."}}]}
            )

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.response == "I see a red square."
            assert result.model == "deepseek-v4-flash-free"
            assert result.processing_ms >= 0

            mock_post.assert_called_once()
            call_kwargs = mock_post.call_args[1]
            assert call_kwargs["json"]["model"] == "deepseek-v4-flash-free"
            assert call_kwargs["json"]["messages"][0]["role"] == "user"
            assert isinstance(call_kwargs["json"]["messages"][0]["content"], list)
            assert call_kwargs["json"]["messages"][0]["content"][0]["type"] == "text"
            assert call_kwargs["json"]["messages"][0]["content"][0]["text"] == "Describe"
            assert call_kwargs["json"]["messages"][0]["content"][1]["type"] == "image_url"
            assert "data:image/png;base64," in call_kwargs["json"]["messages"][0]["content"][1]["image_url"]["url"]

    async def test_analyze_with_custom_model(self, settings: Settings) -> None:
        settings.zen_model = "custom-zen-model"
        provider = create_provider(settings)
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(
                200, {"choices": [{"message": {"content": "Analysis complete."}}]}
            )

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.model == "custom-zen-model"

    async def test_raises_on_http_error(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(500)

            with pytest.raises(httpx.HTTPStatusError):
                await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

    async def test_sends_base64_image(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(
                200, {"choices": [{"message": {"content": "ok"}}]}
            )

            await provider.analyze(image=b"\x89PNG\r\n\x1a\n", prompt="X")

            call_kwargs = mock_post.call_args[1]
            image_url = call_kwargs["json"]["messages"][0]["content"][1]["image_url"]["url"]
            assert image_url.startswith("data:image/png;base64,")
            from base64 import b64decode

            b64_part = image_url.split(",")[1]
            decoded = b64decode(b64_part)
            assert decoded == b"\x89PNG\r\n\x1a\n"

    async def test_sends_jpeg_with_correct_mime(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(
                200, {"choices": [{"message": {"content": "ok"}}]}
            )

            jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00" + b"fake-jpeg-data"
            await provider.analyze(image=jpeg_bytes, prompt="X")

            call_kwargs = mock_post.call_args[1]
            image_url = call_kwargs["json"]["messages"][0]["content"][1]["image_url"]["url"]
            assert image_url.startswith("data:image/jpeg;base64,")

    async def test_sends_api_key(self, provider: AnalysisProvider) -> None:
        with patch.object(httpx.AsyncClient, "post") as mock_post:
            mock_post.return_value = _make_zen_response(
                200, {"choices": [{"message": {"content": "ok"}}]}
            )

            await provider.analyze(image=b"test", prompt="X")

            call_kwargs = mock_post.call_args[1]
            assert call_kwargs["headers"]["Authorization"] == "Bearer test-key-123"


class TestBedrockProvider:
    @pytest.fixture
    def settings(self) -> Settings:
        return Settings(provider="bedrock", default_model="test-model", bedrock_region="us-east-1")

    @pytest.fixture
    def provider(self, settings: Settings) -> BedrockProvider:
        return create_provider(settings)

    async def test_analyze_returns_result(self, provider: BedrockProvider) -> None:
        mock_response = _make_bedrock_response("I see a blue square.", "Reasoning text")

        with patch.object(provider.client, "converse") as mock_converse:
            mock_converse.return_value = mock_response

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.response == "I see a blue square."
            assert result.model == "test-model"
            assert result.processing_ms >= 0

            mock_converse.assert_called_once()
            call_kwargs = mock_converse.call_args[1]
            assert call_kwargs["modelId"] == "test-model"
            assert call_kwargs["messages"][0]["role"] == "user"
            assert "image" in call_kwargs["messages"][0]["content"][0]
            assert call_kwargs["messages"][0]["content"][1]["text"] == "Describe"
            assert call_kwargs["inferenceConfig"]["maxTokens"] == 2000
            assert call_kwargs["inferenceConfig"]["temperature"] == 0.3

    async def test_analyze_with_custom_model(self, settings: Settings) -> None:
        settings.bedrock_model = "custom-bedrock-model"
        provider = create_provider(settings)

        mock_response = _make_bedrock_response("Analysis complete.")

        with patch.object(provider.client, "converse") as mock_converse:
            mock_converse.return_value = mock_response

            result = await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

            assert result.model == "custom-bedrock-model"

    async def test_raises_on_client_error(self, provider: BedrockProvider) -> None:
        with patch.object(provider.client, "converse") as mock_converse:
            error_response = {"Error": {"Code": "ValidationException", "Message": "Invalid input"}}
            mock_converse.side_effect = ClientError(error_response, "Converse")

            with pytest.raises(ClientError):
                await provider.analyze(image=b"fake-png-bytes", prompt="Describe")

    async def test_sends_base64_image(self, provider: BedrockProvider) -> None:
        mock_response = _make_bedrock_response("ok")

        with patch.object(provider.client, "converse") as mock_converse:
            mock_converse.return_value = mock_response

            await provider.analyze(image=b"\x89PNG\r\n\x1a\n", prompt="X")

            call_kwargs = mock_converse.call_args[1]
            image_block = call_kwargs["messages"][0]["content"][0]["image"]
            assert image_block["format"] == "png"
            from base64 import b64decode

            decoded = b64decode(image_block["source"]["bytes"])
            assert decoded == b"\x89PNG\r\n\x1a\n"

    def test_detect_image_format_png(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"\x89PNG\r\n\x1a\n") == "png"

    def test_detect_image_format_jpeg(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"\xff\xd8\xff") == "jpeg"

    def test_detect_image_format_gif87a(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"GIF87a") == "gif"

    def test_detect_image_format_gif89a(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"GIF89a") == "gif"

    def test_detect_image_format_webp(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"RIFFxxxxWEBP") == "webp"

    def test_detect_image_format_unknown_defaults_to_png(self, provider: BedrockProvider) -> None:
        assert provider._detect_image_format(b"unknown") == "png"
