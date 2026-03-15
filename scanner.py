"""Market scanner: finds the best trading opportunities across symbols."""

import logging
from bybit_client import BybitClient
from strategy import klines_to_df, compute_indicators, detect_signal, score_opportunity, Signal

logger = logging.getLogger(__name__)


class Opportunity:
    def __init__(self, symbol: str, signal: str, score: float, details: dict):
        self.symbol = symbol
        self.signal = signal
        self.score = score
        self.details = details

    def __repr__(self):
        return f"Opportunity({self.symbol}, {self.signal}, score={self.score}, {self.details})"


def scan_market(client: BybitClient, top_n: int = 20) -> list[Opportunity]:
    """Scan top symbols by volume and return scored opportunities with signals."""
    symbols = client.get_top_volume_symbols(limit=top_n)
    logger.info(f"Scanning {len(symbols)} symbols...")

    opportunities = []
    for symbol in symbols:
        try:
            klines = client.get_klines(symbol, interval="15", limit=200)
            df = klines_to_df(klines)
            df = compute_indicators(df)

            signal, details = detect_signal(df)
            ticker = client.get_ticker(symbol)
            score = score_opportunity(ticker, df)

            if signal != Signal.NONE and score > 10:
                opportunities.append(Opportunity(symbol, signal, score, details))
                logger.info(f"  {symbol}: {signal} (score={score})")
            else:
                logger.debug(f"  {symbol}: no signal (score={score})")
        except Exception as e:
            logger.warning(f"  {symbol}: scan error - {e}")

    opportunities.sort(key=lambda o: o.score, reverse=True)
    return opportunities
