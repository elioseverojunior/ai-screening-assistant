from __future__ import annotations

from io import BytesIO
from os import environ
from typing import AsyncIterator

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from PIL import Image

environ.setdefault("AI_SERVER_ENVIROMENT", "test")


@pytest.fixture
def settings() -> Settings:
    from ai_server.config import Settings

    return Settings()


@pytest.fixture
def app(settings: Settings) -> FastAPI:
    from ai_server.main import create_app

    return create_app(settings=settings.model_copy(update={"metrics_port": 0}))


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as ac:
        yield ac


@pytest.fixture
def sample_png() -> bytes:
    buf = BytesIO()
    Image.new("RGB", (100, 100), color="red").save(buf, format="PNG")
    return buf.getvalue()
