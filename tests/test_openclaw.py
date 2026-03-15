"""Tests for the OpenClaw agent adapter."""

import os
from unittest.mock import patch
from openclaw_agent import OpenClawAgent


class TestOpenClawDisabled:
    def test_validate_auto_approves(self):
        with patch.dict(os.environ, {"OPENCLAW_ENABLED": "false"}):
            agent = OpenClawAgent()
            result = agent.validate_signal("BTCUSDT", "long", {"rsi": 25})
            assert result["approved"] is True

    def test_recommendations_empty(self):
        with patch.dict(os.environ, {"OPENCLAW_ENABLED": "false"}):
            agent = OpenClawAgent()
            recs = agent.get_recommendations()
            assert recs == []

    def test_report_trade_noop(self):
        with patch.dict(os.environ, {"OPENCLAW_ENABLED": "false"}):
            agent = OpenClawAgent()
            # Should not raise
            agent.report_trade("BTCUSDT", "Buy", 0.001, {"orderId": "123"})
