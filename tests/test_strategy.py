"""Tests for the trading strategy module."""

import pandas as pd
import numpy as np
from strategy import klines_to_df, compute_indicators, detect_signal, score_opportunity, Signal


def make_klines(n=200, start_price=50000):
    """Generate fake kline data for testing."""
    timestamps = [int((1700000000 + i * 900) * 1000) for i in range(n)]
    prices = [start_price + np.sin(i / 10) * 500 + np.random.normal(0, 50) for i in range(n)]
    klines = []
    for i in range(n):
        o = prices[i]
        h = o + abs(np.random.normal(0, 30))
        low = o - abs(np.random.normal(0, 30))
        c = o + np.random.normal(0, 20)
        v = abs(np.random.normal(1000, 200))
        turnover = v * o
        klines.append([str(timestamps[i]), str(o), str(h), str(low), str(c), str(v), str(turnover)])
    # Bybit returns reverse chronological
    klines.reverse()
    return klines


class TestKlinesToDf:
    def test_converts_to_dataframe(self):
        klines = make_klines(50)
        df = klines_to_df(klines)
        assert isinstance(df, pd.DataFrame)
        assert len(df) == 50
        assert list(df.columns) == ["timestamp", "open", "high", "low", "close", "volume", "turnover"]

    def test_sorted_chronologically(self):
        klines = make_klines(50)
        df = klines_to_df(klines)
        assert df["timestamp"].is_monotonic_increasing

    def test_numeric_types(self):
        klines = make_klines(20)
        df = klines_to_df(klines)
        assert df["close"].dtype == np.float64
        assert df["volume"].dtype == np.float64


class TestComputeIndicators:
    def test_adds_indicators(self):
        df = klines_to_df(make_klines(200))
        df = compute_indicators(df)
        assert "rsi" in df.columns
        assert "ema_fast" in df.columns
        assert "ema_slow" in df.columns
        assert "vol_ma" in df.columns

    def test_rsi_range(self):
        df = klines_to_df(make_klines(200))
        df = compute_indicators(df)
        rsi_valid = df["rsi"].dropna()
        assert (rsi_valid >= 0).all()
        assert (rsi_valid <= 100).all()


class TestDetectSignal:
    def test_returns_valid_signal(self):
        df = klines_to_df(make_klines(200))
        df = compute_indicators(df)
        signal, details = detect_signal(df)
        assert signal in (Signal.LONG, Signal.SHORT, Signal.NONE)
        assert isinstance(details, dict)

    def test_insufficient_data_returns_none(self):
        df = klines_to_df(make_klines(5))
        df = compute_indicators(df)
        signal, details = detect_signal(df)
        assert signal == Signal.NONE


class TestScoreOpportunity:
    def test_returns_float(self):
        df = klines_to_df(make_klines(200))
        df = compute_indicators(df)
        ticker = {"bid1Price": "50000", "ask1Price": "50001"}
        score = score_opportunity(ticker, df)
        assert isinstance(score, float)
        assert 0 <= score <= 100

    def test_insufficient_data_returns_zero(self):
        df = klines_to_df(make_klines(5))
        df = compute_indicators(df)
        ticker = {"bid1Price": "50000", "ask1Price": "50001"}
        score = score_opportunity(ticker, df)
        assert score == 0.0
