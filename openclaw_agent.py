"""Optional OpenClaw agent integration.

OpenClaw is an AI-powered trading agent framework. When enabled, signals from
the local strategy are sent to OpenClaw for additional AI-based validation
before execution. OpenClaw can also push its own trade recommendations.

This module is a thin adapter — if OpenClaw is not configured, all methods
are no-ops that pass through signals unchanged.
"""

import logging
import requests
from config import Config

logger = logging.getLogger(__name__)


class OpenClawAgent:
    """Adapter for OpenClaw agent API."""

    def __init__(self):
        self.enabled = Config.OPENCLAW_ENABLED
        self.base_url = Config.OPENCLAW_API_URL.rstrip("/") if Config.OPENCLAW_API_URL else ""
        self.api_key = Config.OPENCLAW_API_KEY
        if self.enabled:
            logger.info(f"OpenClaw agent enabled: {self.base_url}")
        else:
            logger.info("OpenClaw agent disabled")

    def _headers(self) -> dict:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    def validate_signal(self, symbol: str, signal: str, details: dict) -> dict:
        """Send a signal to OpenClaw for AI validation.

        Returns:
            dict with keys:
                - approved (bool): whether OpenClaw approves the trade
                - confidence (float): 0-1 confidence score
                - reason (str): explanation
        """
        if not self.enabled:
            return {"approved": True, "confidence": 1.0, "reason": "OpenClaw disabled, auto-approved"}

        try:
            resp = requests.post(
                f"{self.base_url}/api/v1/validate",
                json={
                    "symbol": symbol,
                    "signal": signal,
                    "indicators": details,
                },
                headers=self._headers(),
                timeout=10,
            )
            resp.raise_for_status()
            result = resp.json()
            logger.info(f"OpenClaw validation for {symbol}: {result}")
            return {
                "approved": result.get("approved", True),
                "confidence": result.get("confidence", 0.5),
                "reason": result.get("reason", ""),
            }
        except Exception as e:
            logger.warning(f"OpenClaw validation failed: {e}. Falling back to auto-approve.")
            return {"approved": True, "confidence": 0.5, "reason": f"OpenClaw unavailable: {e}"}

    def get_recommendations(self) -> list[dict]:
        """Fetch trade recommendations from OpenClaw agent.

        Returns list of dicts: [{symbol, signal, confidence, reason}, ...]
        """
        if not self.enabled:
            return []

        try:
            resp = requests.get(
                f"{self.base_url}/api/v1/recommendations",
                headers=self._headers(),
                timeout=10,
            )
            resp.raise_for_status()
            recs = resp.json().get("recommendations", [])
            logger.info(f"OpenClaw recommendations: {len(recs)} received")
            return recs
        except Exception as e:
            logger.warning(f"OpenClaw recommendations fetch failed: {e}")
            return []

    def report_trade(self, symbol: str, side: str, qty: float, result: dict):
        """Report an executed trade back to OpenClaw for learning."""
        if not self.enabled:
            return

        try:
            requests.post(
                f"{self.base_url}/api/v1/trades",
                json={
                    "symbol": symbol,
                    "side": side,
                    "qty": qty,
                    "result": result,
                },
                headers=self._headers(),
                timeout=5,
            )
        except Exception as e:
            logger.debug(f"OpenClaw trade report failed: {e}")
