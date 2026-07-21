from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from enum import Enum
from typing import TypeVar

from ai_server.logging import get_logger

T = TypeVar("T")

CBallable = Callable[..., Awaitable[T]]

logger = get_logger(__name__)


class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitBreakerOpenError(Exception):
    def __init__(self) -> None:
        super().__init__("Circuit breaker is open")


class CircuitBreaker:
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
    ) -> None:
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout

        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.last_failure_time: float | None = None

    @property
    def is_ready(self) -> bool:
        return self.state != CircuitState.OPEN

    def _try_half_open(self) -> None:
        if (
            self.state == CircuitState.OPEN
            and self.last_failure_time is not None
            and (time.monotonic() - self.last_failure_time) >= self.recovery_timeout
        ):
            logger.info("Circuit breaker transitioning to half-open")
            self.state = CircuitState.HALF_OPEN

    async def acall(self, fn: CBallable[T], *args, **kwargs) -> T:
        self._try_half_open()
        if self.state == CircuitState.OPEN:
            raise CircuitBreakerOpenError()
        try:
            result = await fn(*args, **kwargs)
            self._on_success()
            return result
        except Exception:
            self._on_failure()
            raise

    def _on_success(self) -> None:
        if self.state != CircuitState.CLOSED:
            logger.info("Circuit breaker reset to closed after success")
        self.state = CircuitState.CLOSED
        self.failure_count = 0

    def _on_failure(self) -> None:
        self.failure_count += 1
        self.last_failure_time = time.monotonic()
        if self.state == CircuitState.HALF_OPEN:
            logger.warning("Circuit breaker half-open test failed, back to open")
            self.state = CircuitState.OPEN
        elif self.failure_count >= self.failure_threshold:
            logger.warning("Circuit breaker opened after %d failures", self.failure_count)
            self.state = CircuitState.OPEN

    def reset(self) -> None:
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.last_failure_time = None
