"""Trade executor: manages positions, TP/SL, and risk."""

import logging
from bybit_client import BybitClient
from scanner import Opportunity
from strategy import Signal
from config import Config

logger = logging.getLogger(__name__)


class Trader:
    def __init__(self, client: BybitClient):
        self.client = client
        self.max_open_positions = 3

    def execute_opportunity(self, opp: Opportunity) -> dict | None:
        """Take a trade based on a scanned opportunity."""
        # Check if we already have a position on this symbol
        existing = self.client.get_positions(opp.symbol)
        if existing:
            logger.info(f"Already have position on {opp.symbol}, skipping")
            return None

        # Check max open positions
        all_positions = self.client.get_positions()
        if len(all_positions) >= self.max_open_positions:
            logger.info(f"Max open positions ({self.max_open_positions}) reached, skipping")
            return None

        # Set leverage
        self.client.set_leverage(opp.symbol, Config.LEVERAGE)

        # Determine side, TP, SL
        price = opp.details.get("price", 0)
        if price <= 0:
            ticker = self.client.get_ticker(opp.symbol)
            price = float(ticker["lastPrice"])

        if opp.signal == Signal.LONG:
            side = "Buy"
            tp = price * (1 + Config.TAKE_PROFIT_PCT / 100)
            sl = price * (1 - Config.STOP_LOSS_PCT / 100)
        elif opp.signal == Signal.SHORT:
            side = "Sell"
            tp = price * (1 - Config.TAKE_PROFIT_PCT / 100)
            sl = price * (1 + Config.STOP_LOSS_PCT / 100)
        else:
            return None

        logger.info(
            f"Executing {side} on {opp.symbol} | "
            f"qty={Config.TRADE_QTY} price~{price:.2f} TP={tp:.2f} SL={sl:.2f} "
            f"score={opp.score}"
        )

        result = self.client.place_order(
            symbol=opp.symbol,
            side=side,
            qty=Config.TRADE_QTY,
            take_profit=tp,
            stop_loss=sl,
        )
        return result

    def check_positions(self) -> list[dict]:
        """Log current open positions."""
        positions = self.client.get_positions()
        if not positions:
            logger.info("No open positions")
            return []

        for p in positions:
            pnl = float(p.get("unrealisedPnl", 0))
            side = p.get("side", "?")
            size = p.get("size", "0")
            symbol = p.get("symbol", "?")
            entry = p.get("avgPrice", "?")
            logger.info(
                f"Position: {side} {size} {symbol} @ {entry} | PnL: {pnl:.4f} USDT"
            )
        return positions

    def close_all_positions(self):
        """Close all open positions."""
        positions = self.client.get_positions()
        for p in positions:
            symbol = p["symbol"]
            side = p["side"]
            size = float(p["size"])
            logger.info(f"Closing {side} {size} {symbol}")
            self.client.close_position(symbol, side, size)
        logger.info(f"Closed {len(positions)} positions")
