from __future__ import annotations

from ai_server.config import Settings


class TestSettingsDefaults:
    def test_host_default(self) -> None:
        assert Settings().host == "0.0.0.0"

    def test_port_default(self) -> None:
        assert Settings().port == 8000

    def test_default_model(self) -> None:
        assert Settings().default_model == "llama3.2-vision"

    def test_provider_default(self) -> None:
        assert Settings().provider == "ollama"

    def test_ollama_base_url_default(self) -> None:
        assert Settings().ollama_base_url == "http://localhost:11434"


class TestSettingsResolveModel:
    def test_resolve_uses_default_when_no_provider_model(self) -> None:
        s = Settings(provider="ollama")
        assert s.resolve_model() == "llama3.2-vision"

    def test_resolve_uses_ollama_model_when_set(self) -> None:
        s = Settings(provider="ollama", ollama_model="llama3.2-vision")
        assert s.resolve_model() == "llama3.2-vision"

    def test_resolve_custom_default_model(self) -> None:
        s = Settings(default_model="gemma-3-12b")
        assert s.resolve_model() == "gemma-3-12b"

    def test_resolve_with_all_provider_specific_models(self) -> None:
        cases = [
            ("ollama", "ollama_model", "ollama-vision"),
            ("huggingface", "huggingface_model", "hf-vision"),
            ("groq", "groq_model", "groq-vision"),
            ("gemini", "gemini_model", "gemini-vision"),
            ("cloudflare", "cloudflare_model", "cf-vision"),
        ]
        for provider, field, model_name in cases:
            s = Settings(**{field: model_name, "provider": provider})
            assert s.resolve_model() == model_name, f"failed for {provider}"

    def test_from_env_file(self) -> None:
        s = Settings.from_env_file()
        assert isinstance(s, Settings)

    def test_get_settings_returns_defaults(self) -> None:
        from ai_server.config import get_settings

        s = get_settings()
        assert isinstance(s, Settings)
