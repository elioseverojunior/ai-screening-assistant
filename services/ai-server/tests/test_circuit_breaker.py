from __future__ import annotations

import pytest

from ai_server.circuit_breaker import CircuitBreaker, CircuitBreakerOpenError, CircuitState


class TestCircuitBreaker:
    def test_starts_closed(self) -> None:
        cb = CircuitBreaker()
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0
        assert cb.is_ready is True

    async def test_acall_success_resets_failures(self) -> None:
        cb = CircuitBreaker()

        async def ok() -> str:
            return "done"

        result = await cb.acall(ok)
        assert result == "done"
        assert cb.failure_count == 0
        assert cb.state == CircuitState.CLOSED

    async def test_acall_failure_increments_counter(self) -> None:
        cb = CircuitBreaker(failure_threshold=3)

        async def fail() -> str:
            msg = "boom"
            raise RuntimeError(msg)

        with pytest.raises(RuntimeError, match="boom"):
            await cb.acall(fail)
        assert cb.failure_count == 1
        assert cb.state == CircuitState.CLOSED

    async def test_acall_opens_after_threshold(self) -> None:
        cb = CircuitBreaker(failure_threshold=2)

        async def fail() -> str:
            raise RuntimeError("boom")

        for _ in range(2):
            with pytest.raises(RuntimeError):
                await cb.acall(fail)
        assert cb.state == CircuitState.OPEN
        assert cb.is_ready is False

    async def test_acall_raises_when_open(self) -> None:
        cb = CircuitBreaker(failure_threshold=1)

        async def fail() -> str:
            raise RuntimeError("boom")

        with pytest.raises(RuntimeError):
            await cb.acall(fail)
        assert cb.state == CircuitState.OPEN

        async def ok() -> str:
            return "done"

        with pytest.raises(CircuitBreakerOpenError):
            await cb.acall(ok)

    async def test_half_open_transition_on_success(self) -> None:
        cb = CircuitBreaker(failure_threshold=1, recovery_timeout=-1)

        async def fail() -> str:
            raise RuntimeError("boom")

        with pytest.raises(RuntimeError):
            await cb.acall(fail)
        assert cb.state == CircuitState.OPEN

        async def ok() -> str:
            return "done"

        result = await cb.acall(ok)
        assert result == "done"
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0

    async def test_half_open_fails_back_to_open(self) -> None:
        cb = CircuitBreaker(failure_threshold=1, recovery_timeout=-1)

        async def fail() -> str:
            raise RuntimeError("boom")

        with pytest.raises(RuntimeError):
            await cb.acall(fail)
        assert cb.state == CircuitState.OPEN

        with pytest.raises(RuntimeError):
            await cb.acall(fail)
        assert cb.state == CircuitState.OPEN
        assert cb.failure_count == 2

    def test_reset(self) -> None:
        cb = CircuitBreaker(failure_threshold=1)
        cb.failure_count = 5
        cb.state = CircuitState.OPEN
        cb.reset()
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0
        assert cb.last_failure_time is None
