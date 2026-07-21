from __future__ import annotations

import json
import logging
import re

from ai_server.logging import JsonFormatter, get_logger, setup_logging


class TestJsonFormatter:
    def test_format_basic(self) -> None:
        record = logging.LogRecord(
            name="ai_server.test",
            level=logging.INFO,
            pathname=__file__,
            lineno=10,
            msg="hello world",
            args=(),
            exc_info=None,
        )
        formatter = JsonFormatter()
        output = formatter.format(record)
        parsed = json.loads(output)
        assert parsed["level"] == "INFO"
        assert parsed["message"] == "hello world"
        assert parsed["logger"] == "ai_server.test"
        assert parsed["module"] == "test_logging"
        assert "timestamp" in parsed

    def test_format_with_exception(self) -> None:
        import sys

        try:
            raise ValueError("test error")
        except ValueError:
            record = logging.LogRecord(
                name="ai_server.test",
                level=logging.ERROR,
                pathname=__file__,
                lineno=20,
                msg="something failed",
                args=(),
                exc_info=sys.exc_info(),
            )
        formatter = JsonFormatter()
        output = formatter.format(record)
        parsed = json.loads(output)
        assert parsed["level"] == "ERROR"
        assert "exception" in parsed
        assert "ValueError" in parsed["exception"]
        assert "test error" in parsed["exception"]

    def test_format_with_props(self) -> None:
        record = logging.LogRecord(
            name="ai_server.test",
            level=logging.INFO,
            pathname=__file__,
            lineno=30,
            msg="with props",
            args=(),
            exc_info=None,
        )
        record.props = {"request_id": "abc-123", "duration_ms": 42}
        formatter = JsonFormatter()
        output = formatter.format(record)
        parsed = json.loads(output)
        assert parsed["request_id"] == "abc-123"
        assert parsed["duration_ms"] == 42


class TestSetupLogging:
    def test_logger_is_configured(self) -> None:
        logger = logging.getLogger("ai_server")
        handlers_before = len(logger.handlers)
        setup_logging("DEBUG")
        assert len(logger.handlers) > 0
        assert logger.level == logging.DEBUG


class TestGetLogger:
    def test_returns_named_logger(self) -> None:
        logger = get_logger("mymodule")
        assert logger.name == "ai_server.mymodule"
