import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    # Bybit
    BYBIT_API_KEY = os.getenv("BYBIT_API_KEY", "")
    BYBIT_API_SECRET = os.getenv("BYBIT_API_SECRET", "")
    BYBIT_TESTNET = os.getenv("BYBIT_TESTNET", "true").lower() == "true"

    # Trading
    SYMBOL = os.getenv("SYMBOL", "BTCUSDT")
    TRADE_QTY = float(os.getenv("TRADE_QTY", "0.001"))
    LEVERAGE = int(os.getenv("LEVERAGE", "5"))
    TAKE_PROFIT_PCT = float(os.getenv("TAKE_PROFIT_PCT", "2.0"))
    STOP_LOSS_PCT = float(os.getenv("STOP_LOSS_PCT", "1.0"))

    # Strategy
    RSI_PERIOD = int(os.getenv("RSI_PERIOD", "14"))
    RSI_OVERBOUGHT = float(os.getenv("RSI_OVERBOUGHT", "70"))
    RSI_OVERSOLD = float(os.getenv("RSI_OVERSOLD", "30"))
    EMA_FAST = int(os.getenv("EMA_FAST", "9"))
    EMA_SLOW = int(os.getenv("EMA_SLOW", "21"))
    SCAN_INTERVAL_SECONDS = int(os.getenv("SCAN_INTERVAL_SECONDS", "60"))

    # OpenClaw
    OPENCLAW_ENABLED = os.getenv("OPENCLAW_ENABLED", "false").lower() == "true"
    OPENCLAW_API_URL = os.getenv("OPENCLAW_API_URL", "")
    OPENCLAW_API_KEY = os.getenv("OPENCLAW_API_KEY", "")
