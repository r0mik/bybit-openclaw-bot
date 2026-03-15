#!/usr/bin/env python3
"""Bybit Trading Bot - finds profitable positions and trades them.

Usage:
    python bot.py              # Run the bot loop
    python bot.py --scan       # One-time market scan (no trading)
    python bot.py --positions  # Show current positions
    python bot.py --close-all  # Close all open positions
"""

import argparse
import logging
import time
import sys

from config import Config
from bybit_client import BybitClient
from scanner import scan_market
from trader import Trader
from openclaw_agent import OpenClawAgent
from strategy import Signal

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("bot")


def run_scan(client: BybitClient):
    """Scan the market and print opportunities."""
    opps = scan_market(client)
    if not opps:
        print("\nNo trading opportunities found right now.")
        return opps

    print(f"\n{'='*70}")
    print(f"  Found {len(opps)} opportunities:")
    print(f"{'='*70}")
    for i, opp in enumerate(opps, 1):
        arrow = "▲ LONG" if opp.signal == Signal.LONG else "▼ SHORT"
        print(
            f"  {i}. {opp.symbol:<12} {arrow:<10} "
            f"Score: {opp.score:>6.1f}  "
            f"RSI: {opp.details.get('rsi', '-'):>6}  "
            f"Price: {opp.details.get('price', '-')}"
        )
    print(f"{'='*70}\n")
    return opps


def run_bot_loop(client: BybitClient, trader: Trader, openclaw: OpenClawAgent):
    """Main bot loop: scan → validate → trade → repeat."""
    logger.info("Starting bot loop...")

    # Show balance
    try:
        balance = client.get_wallet_balance()
        coins = balance.get("coin", [])
        usdt = next((c for c in coins if c["coin"] == "USDT"), None)
        if usdt:
            logger.info(f"Wallet balance: {usdt['walletBalance']} USDT (available: {usdt['availableToWithdraw']})")
    except Exception as e:
        logger.warning(f"Could not fetch balance: {e}")

    while True:
        try:
            # 1. Check existing positions
            trader.check_positions()

            # 2. Scan market for opportunities
            opportunities = scan_market(client)

            # 3. Process top opportunities
            for opp in opportunities[:3]:  # top 3
                # Optional: validate with OpenClaw
                validation = openclaw.validate_signal(opp.symbol, opp.signal, opp.details)
                if not validation["approved"]:
                    logger.info(
                        f"OpenClaw rejected {opp.symbol}: {validation['reason']} "
                        f"(confidence={validation['confidence']})"
                    )
                    continue

                # Execute trade
                result = trader.execute_opportunity(opp)
                if result:
                    openclaw.report_trade(
                        opp.symbol,
                        "Buy" if opp.signal == Signal.LONG else "Sell",
                        Config.TRADE_QTY,
                        result,
                    )

            logger.info(f"Sleeping {Config.SCAN_INTERVAL_SECONDS}s until next scan...")
            time.sleep(Config.SCAN_INTERVAL_SECONDS)

        except KeyboardInterrupt:
            logger.info("Bot stopped by user")
            break
        except Exception as e:
            logger.error(f"Bot loop error: {e}", exc_info=True)
            time.sleep(30)


def main():
    parser = argparse.ArgumentParser(description="Bybit Trading Bot")
    parser.add_argument("--scan", action="store_true", help="One-time market scan (no trading)")
    parser.add_argument("--positions", action="store_true", help="Show current positions")
    parser.add_argument("--close-all", action="store_true", help="Close all open positions")
    args = parser.parse_args()

    if not Config.BYBIT_API_KEY or not Config.BYBIT_API_SECRET:
        print("Error: Set BYBIT_API_KEY and BYBIT_API_SECRET in .env file")
        print("See .env.example for configuration options")
        sys.exit(1)

    client = BybitClient()
    trader = Trader(client)
    openclaw = OpenClawAgent()

    if args.scan:
        run_scan(client)
    elif args.positions:
        positions = trader.check_positions()
        if positions:
            for p in positions:
                pnl = float(p.get("unrealisedPnl", 0))
                print(
                    f"  {p['side']:<4} {p['size']} {p['symbol']:<12} "
                    f"@ {p['avgPrice']}  PnL: {pnl:+.4f} USDT"
                )
    elif args.close_all:
        trader.close_all_positions()
    else:
        env = "TESTNET" if Config.BYBIT_TESTNET else "⚠️  MAINNET"
        print(f"\n  Bybit Trading Bot ({env})")
        print(f"  Symbol scan: top 20 by volume")
        print(f"  Strategy: RSI({Config.RSI_PERIOD}) + EMA({Config.EMA_FAST}/{Config.EMA_SLOW})")
        print(f"  Trade size: {Config.TRADE_QTY} | Leverage: {Config.LEVERAGE}x")
        print(f"  TP: {Config.TAKE_PROFIT_PCT}% | SL: {Config.STOP_LOSS_PCT}%")
        print(f"  OpenClaw: {'enabled' if Config.OPENCLAW_ENABLED else 'disabled'}")
        print(f"  Scan interval: {Config.SCAN_INTERVAL_SECONDS}s")
        print()
        run_bot_loop(client, trader, openclaw)


if __name__ == "__main__":
    main()
