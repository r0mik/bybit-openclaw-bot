"""Trading strategy: RSI + EMA crossover with volume confirmation."""

import logging
import pandas as pd
import numpy as np
from ta.momentum import RSIIndicator
from ta.trend import EMAIndicator
from ta.volume import VolumeWeightedAveragePrice
from config import Config

logger = logging.getLogger(__name__)


class Signal:
    LONG = "long"
    SHORT = "short"
    NONE = "none"


def klines_to_df(klines: list) -> pd.DataFrame:
    """Convert Bybit kline response to a DataFrame.

    Bybit returns: [startTime, openPrice, highPrice, lowPrice, closePrice, volume, turnover]
    in reverse chronological order.
    """
    df = pd.DataFrame(
        klines,
        columns=["timestamp", "open", "high", "low", "close", "volume", "turnover"],
    )
    df = df.astype({
        "open": float, "high": float, "low": float,
        "close": float, "volume": float, "turnover": float,
    })
    df["timestamp"] = pd.to_datetime(df["timestamp"].astype(int), unit="ms")
    df = df.sort_values("timestamp").reset_index(drop=True)
    return df


def compute_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Add RSI, EMA fast/slow, and VWAP indicators to the dataframe."""
    df["rsi"] = RSIIndicator(df["close"], window=Config.RSI_PERIOD).rsi()
    df["ema_fast"] = EMAIndicator(df["close"], window=Config.EMA_FAST).ema_indicator()
    df["ema_slow"] = EMAIndicator(df["close"], window=Config.EMA_SLOW).ema_indicator()

    # Volume moving average for confirmation
    df["vol_ma"] = df["volume"].rolling(window=20).mean()

    return df


def detect_signal(df: pd.DataFrame) -> tuple[str, dict]:
    """Analyze indicators and return a trading signal with metadata.

    Strategy logic:
    - LONG: RSI < oversold AND EMA fast crosses above EMA slow AND volume > avg
    - SHORT: RSI > overbought AND EMA fast crosses below EMA slow AND volume > avg

    Returns (signal_type, details_dict)
    """
    if len(df) < max(Config.RSI_PERIOD, Config.EMA_SLOW) + 5:
        return Signal.NONE, {}

    latest = df.iloc[-1]
    prev = df.iloc[-2]

    rsi = latest["rsi"]
    ema_fast = latest["ema_fast"]
    ema_slow = latest["ema_slow"]
    prev_ema_fast = prev["ema_fast"]
    prev_ema_slow = prev["ema_slow"]
    volume = latest["volume"]
    vol_ma = latest["vol_ma"]

    if any(pd.isna([rsi, ema_fast, ema_slow, prev_ema_fast, prev_ema_slow, vol_ma])):
        return Signal.NONE, {}

    details = {
        "rsi": round(rsi, 2),
        "ema_fast": round(ema_fast, 2),
        "ema_slow": round(ema_slow, 2),
        "price": round(latest["close"], 2),
        "volume_ratio": round(volume / vol_ma, 2) if vol_ma > 0 else 0,
    }

    volume_ok = volume > vol_ma

    # Bullish: EMA fast crosses above slow + RSI oversold + volume confirmation
    ema_cross_up = prev_ema_fast <= prev_ema_slow and ema_fast > ema_slow
    if ema_cross_up and rsi < Config.RSI_OVERSOLD and volume_ok:
        logger.info(f"LONG signal detected: {details}")
        return Signal.LONG, details

    # Bearish: EMA fast crosses below slow + RSI overbought + volume confirmation
    ema_cross_down = prev_ema_fast >= prev_ema_slow and ema_fast < ema_slow
    if ema_cross_down and rsi > Config.RSI_OVERBOUGHT and volume_ok:
        logger.info(f"SHORT signal detected: {details}")
        return Signal.SHORT, details

    return Signal.NONE, details


def score_opportunity(ticker: dict, df: pd.DataFrame) -> float:
    """Score a symbol's trading opportunity from 0-100.

    Higher score = more attractive opportunity.
    Considers: RSI extremes, trend strength, volume, spread.
    """
    if len(df) < max(Config.RSI_PERIOD, Config.EMA_SLOW) + 5:
        return 0.0

    latest = df.iloc[-1]
    rsi = latest.get("rsi", 50)
    ema_fast = latest.get("ema_fast", 0)
    ema_slow = latest.get("ema_slow", 0)
    volume = latest.get("volume", 0)
    vol_ma = latest.get("vol_ma", 1)

    if any(pd.isna([rsi, ema_fast, ema_slow, vol_ma])) or vol_ma == 0:
        return 0.0

    score = 0.0

    # RSI extremes (max 30 points)
    if rsi < Config.RSI_OVERSOLD:
        score += 30 * (1 - rsi / Config.RSI_OVERSOLD)
    elif rsi > Config.RSI_OVERBOUGHT:
        score += 30 * ((rsi - Config.RSI_OVERBOUGHT) / (100 - Config.RSI_OVERBOUGHT))

    # Trend strength via EMA spread (max 30 points)
    ema_spread = abs(ema_fast - ema_slow) / ema_slow * 100 if ema_slow else 0
    score += min(30, ema_spread * 10)

    # Volume spike (max 20 points)
    vol_ratio = volume / vol_ma if vol_ma > 0 else 0
    score += min(20, (vol_ratio - 1) * 10) if vol_ratio > 1 else 0

    # Spread / liquidity from ticker (max 20 points)
    bid = float(ticker.get("bid1Price", 0))
    ask = float(ticker.get("ask1Price", 0))
    if bid > 0 and ask > 0:
        spread_pct = (ask - bid) / bid * 100
        score += max(0, 20 - spread_pct * 100)  # tighter spread = higher score

    return round(min(100, max(0, score)), 2)
