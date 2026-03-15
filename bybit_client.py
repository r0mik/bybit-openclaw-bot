"""Bybit API client wrapper for testnet/mainnet trading."""

import logging
from pybit.unified_trading import HTTP
from config import Config

logger = logging.getLogger(__name__)


class BybitClient:
    def __init__(self):
        self.client = HTTP(
            testnet=Config.BYBIT_TESTNET,
            api_key=Config.BYBIT_API_KEY,
            api_secret=Config.BYBIT_API_SECRET,
        )
        env = "TESTNET" if Config.BYBIT_TESTNET else "MAINNET"
        logger.info(f"Bybit client initialized ({env})")

    def get_klines(self, symbol: str, interval: str = "15", limit: int = 200) -> list:
        """Fetch candlestick data. interval: 1,3,5,15,30,60,120,240,360,720,D,W,M"""
        resp = self.client.get_kline(
            category="linear", symbol=symbol, interval=interval, limit=limit
        )
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get klines: {resp['retMsg']}")
        return resp["result"]["list"]

    def get_ticker(self, symbol: str) -> dict:
        """Get latest ticker for a symbol."""
        resp = self.client.get_tickers(category="linear", symbol=symbol)
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get ticker: {resp['retMsg']}")
        return resp["result"]["list"][0]

    def get_instruments(self, symbol: str = None) -> list:
        """Get instrument info for available trading pairs."""
        params = {"category": "linear"}
        if symbol:
            params["symbol"] = symbol
        resp = self.client.get_instruments_info(**params)
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get instruments: {resp['retMsg']}")
        return resp["result"]["list"]

    def set_leverage(self, symbol: str, leverage: int):
        """Set leverage for a symbol."""
        try:
            self.client.set_leverage(
                category="linear",
                symbol=symbol,
                buyLeverage=str(leverage),
                sellLeverage=str(leverage),
            )
            logger.info(f"Leverage set to {leverage}x for {symbol}")
        except Exception as e:
            if "leverage not modified" in str(e).lower() or "110043" in str(e):
                logger.debug(f"Leverage already set to {leverage}x for {symbol}")
            else:
                raise

    def place_order(
        self,
        symbol: str,
        side: str,
        qty: float,
        take_profit: float = None,
        stop_loss: float = None,
    ) -> dict:
        """Place a market order with optional TP/SL."""
        params = {
            "category": "linear",
            "symbol": symbol,
            "side": side,
            "orderType": "Market",
            "qty": str(qty),
        }
        if take_profit:
            params["takeProfit"] = str(round(take_profit, 2))
        if stop_loss:
            params["stopLoss"] = str(round(stop_loss, 2))

        resp = self.client.place_order(**params)
        if resp["retCode"] != 0:
            raise Exception(f"Order failed: {resp['retMsg']}")
        logger.info(f"Order placed: {side} {qty} {symbol} | TP={take_profit} SL={stop_loss}")
        return resp["result"]

    def get_positions(self, symbol: str = None) -> list:
        """Get open positions."""
        params = {"category": "linear", "settleCoin": "USDT"}
        if symbol:
            params["symbol"] = symbol
        resp = self.client.get_positions(**params)
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get positions: {resp['retMsg']}")
        return [p for p in resp["result"]["list"] if float(p.get("size", 0)) > 0]

    def close_position(self, symbol: str, side: str, qty: float) -> dict:
        """Close a position by placing an opposite market order."""
        close_side = "Sell" if side == "Buy" else "Buy"
        return self.place_order(symbol, close_side, qty)

    def get_wallet_balance(self) -> dict:
        """Get USDT wallet balance."""
        resp = self.client.get_wallet_balance(accountType="UNIFIED")
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get balance: {resp['retMsg']}")
        return resp["result"]["list"][0]

    def get_top_volume_symbols(self, limit: int = 20) -> list[str]:
        """Get top traded USDT perpetual symbols by 24h volume."""
        resp = self.client.get_tickers(category="linear")
        if resp["retCode"] != 0:
            raise Exception(f"Failed to get tickers: {resp['retMsg']}")
        tickers = [
            t for t in resp["result"]["list"]
            if t["symbol"].endswith("USDT")
        ]
        tickers.sort(key=lambda t: float(t["turnover24h"]), reverse=True)
        return [t["symbol"] for t in tickers[:limit]]
