"""Flask web application for the Bybit trading bot dashboard."""

import logging
import threading

from flask import Flask, jsonify, request, render_template
from flask_socketio import SocketIO

from models import SessionLocal, Bot, Trade, BotTemplate, init_db
from config import Config
from bybit_client import BybitClient
from strategy import klines_to_df, compute_indicators, detect_signal, score_opportunity, Signal
from trader import Trader
from openclaw_agent import OpenClawAgent

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("web_app")

app = Flask(__name__)
app.config["SECRET_KEY"] = "trading-bot-secret"
socketio = SocketIO(app, cors_allowed_origins="*")

# Track running bot threads
_bot_threads: dict[int, threading.Event] = {}


def _get_client():
    """Get a BybitClient instance, or None if not configured."""
    if not Config.BYBIT_API_KEY or not Config.BYBIT_API_SECRET:
        return None
    return BybitClient()


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("index.html")


# ---------------------------------------------------------------------------
# Bot CRUD API
# ---------------------------------------------------------------------------

@app.route("/api/bots", methods=["GET"])
def list_bots():
    db = SessionLocal()
    try:
        query = db.query(Bot)

        status = request.args.get("status")
        if status:
            query = query.filter(Bot.status == status)

        symbol = request.args.get("symbol")
        if symbol:
            query = query.filter(Bot.symbol.ilike(f"%{symbol}%"))

        strategy = request.args.get("strategy")
        if strategy:
            query = query.filter(Bot.strategy == strategy)

        bots = query.order_by(Bot.created_at.desc()).all()
        return jsonify([b.to_dict() for b in bots])
    finally:
        db.close()


@app.route("/api/bots", methods=["POST"])
def create_bot():
    data = request.json
    db = SessionLocal()
    try:
        bot = Bot(
            name=data.get("name", f"Bot-{data.get('symbol', 'BTCUSDT')}"),
            symbol=data.get("symbol", "BTCUSDT").upper(),
            strategy=data.get("strategy", "rsi_ema"),
            side=data.get("side"),
            trade_qty=float(data.get("trade_qty", Config.TRADE_QTY)),
            leverage=int(data.get("leverage", Config.LEVERAGE)),
            take_profit_pct=float(data.get("take_profit_pct", Config.TAKE_PROFIT_PCT)),
            stop_loss_pct=float(data.get("stop_loss_pct", Config.STOP_LOSS_PCT)),
            rsi_period=int(data.get("rsi_period", Config.RSI_PERIOD)),
            rsi_overbought=float(data.get("rsi_overbought", Config.RSI_OVERBOUGHT)),
            rsi_oversold=float(data.get("rsi_oversold", Config.RSI_OVERSOLD)),
            ema_fast=int(data.get("ema_fast", Config.EMA_FAST)),
            ema_slow=int(data.get("ema_slow", Config.EMA_SLOW)),
            scan_interval=int(data.get("scan_interval", Config.SCAN_INTERVAL_SECONDS)),
        )
        db.add(bot)
        db.commit()
        db.refresh(bot)
        return jsonify(bot.to_dict()), 201
    finally:
        db.close()


@app.route("/api/bots/<int:bot_id>", methods=["GET"])
def get_bot(bot_id):
    db = SessionLocal()
    try:
        bot = db.get(Bot, bot_id)
        if not bot:
            return jsonify({"error": "Bot not found"}), 404
        return jsonify(bot.to_dict())
    finally:
        db.close()


@app.route("/api/bots/<int:bot_id>", methods=["PUT"])
def update_bot(bot_id):
    data = request.json
    db = SessionLocal()
    try:
        bot = db.get(Bot, bot_id)
        if not bot:
            return jsonify({"error": "Bot not found"}), 404
        for key in ("name", "symbol", "strategy", "side", "trade_qty", "leverage",
                     "take_profit_pct", "stop_loss_pct", "rsi_period", "rsi_overbought",
                     "rsi_oversold", "ema_fast", "ema_slow", "scan_interval"):
            if key in data:
                setattr(bot, key, data[key])
        db.commit()
        db.refresh(bot)
        return jsonify(bot.to_dict())
    finally:
        db.close()


@app.route("/api/bots/<int:bot_id>", methods=["DELETE"])
def delete_bot(bot_id):
    _stop_bot_thread(bot_id)
    db = SessionLocal()
    try:
        bot = db.get(Bot, bot_id)
        if not bot:
            return jsonify({"error": "Bot not found"}), 404
        db.delete(bot)
        db.commit()
        return jsonify({"ok": True})
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Bot start / stop
# ---------------------------------------------------------------------------

def _bot_loop(bot_id: int, stop_event: threading.Event):
    """Background loop for a single bot."""
    client = _get_client()
    if not client:
        _set_bot_status(bot_id, "error", "Bybit API not configured")
        return

    trader = Trader(client)
    openclaw = OpenClawAgent()

    while not stop_event.is_set():
        db = SessionLocal()
        try:
            bot = db.get(Bot, bot_id)
            if not bot or bot.status != "running":
                break

            # Check positions
            trader.check_positions()

            # Scan for opportunities on this bot's symbol
            klines = client.get_klines(bot.symbol, interval="15", limit=200)
            df = klines_to_df(klines)
            df = compute_indicators(df)
            signal, details = detect_signal(df)
            ticker = client.get_ticker(bot.symbol)
            score = score_opportunity(ticker, df)

            # Emit live update
            socketio.emit("bot_update", {
                "bot_id": bot_id,
                "symbol": bot.symbol,
                "signal": signal,
                "score": score,
                "details": details,
                "price": float(ticker.get("lastPrice", 0)),
            })

            if signal != Signal.NONE and score > 10:
                # If bot has a forced side, filter
                if bot.side and bot.side.lower() != signal:
                    logger.info(f"Bot {bot_id}: signal {signal} doesn't match side {bot.side}, skipping")
                else:
                    from scanner import Opportunity
                    opp = Opportunity(bot.symbol, signal, score, details)

                    validation = openclaw.validate_signal(opp.symbol, opp.signal, opp.details)
                    if validation["approved"]:
                        result = trader.execute_opportunity(opp)
                        if result:
                            trade = Trade(
                                bot_id=bot_id,
                                symbol=bot.symbol,
                                side="Buy" if signal == Signal.LONG else "Sell",
                                qty=bot.trade_qty,
                                entry_price=details.get("price"),
                                take_profit=details.get("price", 0) * (1 + bot.take_profit_pct / 100),
                                stop_loss=details.get("price", 0) * (1 - bot.stop_loss_pct / 100),
                                signal_score=score,
                                signal_details=details,
                                order_id=result.get("orderId"),
                            )
                            db.add(trade)
                            db.commit()
                            socketio.emit("new_trade", trade.to_dict())

            interval = bot.scan_interval or 60
        except Exception as e:
            logger.error(f"Bot {bot_id} error: {e}", exc_info=True)
            _set_bot_status(bot_id, "error", str(e))
            socketio.emit("bot_update", {"bot_id": bot_id, "error": str(e)})
            interval = 30
        finally:
            db.close()

        stop_event.wait(interval)

    _set_bot_status(bot_id, "stopped")


def _set_bot_status(bot_id: int, status: str, error: str = None):
    db = SessionLocal()
    try:
        bot = db.get(Bot, bot_id)
        if bot:
            bot.status = status
            bot.error_message = error
            db.commit()
    finally:
        db.close()


def _stop_bot_thread(bot_id: int):
    event = _bot_threads.pop(bot_id, None)
    if event:
        event.set()


@app.route("/api/bots/<int:bot_id>/start", methods=["POST"])
def start_bot(bot_id):
    db = SessionLocal()
    try:
        bot = db.get(Bot, bot_id)
        if not bot:
            return jsonify({"error": "Bot not found"}), 404
        if bot_id in _bot_threads:
            return jsonify({"error": "Bot already running"}), 400
        bot.status = "running"
        bot.error_message = None
        db.commit()
    finally:
        db.close()

    stop_event = threading.Event()
    _bot_threads[bot_id] = stop_event
    t = threading.Thread(target=_bot_loop, args=(bot_id, stop_event), daemon=True)
    t.start()
    return jsonify({"ok": True, "status": "running"})


@app.route("/api/bots/<int:bot_id>/stop", methods=["POST"])
def stop_bot(bot_id):
    _stop_bot_thread(bot_id)
    _set_bot_status(bot_id, "stopped")
    return jsonify({"ok": True, "status": "stopped"})


# ---------------------------------------------------------------------------
# Positions API (live from Bybit)
# ---------------------------------------------------------------------------

@app.route("/api/positions", methods=["GET"])
def list_positions():
    client = _get_client()
    if not client:
        return jsonify([])
    try:
        positions = client.get_positions()
        result = []
        for p in positions:
            result.append({
                "symbol": p.get("symbol"),
                "side": p.get("side"),
                "size": p.get("size"),
                "entry_price": p.get("avgPrice"),
                "mark_price": p.get("markPrice"),
                "liq_price": p.get("liqPrice"),
                "unrealised_pnl": float(p.get("unrealisedPnl", 0)),
                "leverage": p.get("leverage"),
                "take_profit": p.get("takeProfit"),
                "stop_loss": p.get("stopLoss"),
                "created_time": p.get("createdTime"),
            })
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Trades API (from DB)
# ---------------------------------------------------------------------------

@app.route("/api/trades", methods=["GET"])
def list_trades():
    db = SessionLocal()
    try:
        query = db.query(Trade)
        bot_id = request.args.get("bot_id")
        if bot_id:
            query = query.filter(Trade.bot_id == int(bot_id))
        symbol = request.args.get("symbol")
        if symbol:
            query = query.filter(Trade.symbol.ilike(f"%{symbol}%"))
        status = request.args.get("status")
        if status:
            query = query.filter(Trade.status == status)
        trades = query.order_by(Trade.opened_at.desc()).limit(100).all()
        return jsonify([t.to_dict() for t in trades])
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Market data API (for charts)
# ---------------------------------------------------------------------------

@app.route("/api/market/klines/<symbol>", methods=["GET"])
def get_klines(symbol):
    client = _get_client()
    if not client:
        return jsonify({"error": "Bybit API not configured"}), 500
    interval = request.args.get("interval", "15")
    limit = min(int(request.args.get("limit", "200")), 1000)
    try:
        klines = client.get_klines(symbol.upper(), interval=interval, limit=limit)
        df = klines_to_df(klines)
        df = compute_indicators(df)
        signal, details = detect_signal(df)

        candles = []
        for _, row in df.iterrows():
            candles.append({
                "time": int(row["timestamp"].timestamp()),
                "open": row["open"],
                "high": row["high"],
                "low": row["low"],
                "close": row["close"],
                "volume": row["volume"],
            })

        indicators = {}
        for col in ("rsi", "ema_fast", "ema_slow"):
            indicators[col] = [
                {"time": int(row["timestamp"].timestamp()), "value": round(row[col], 4)}
                for _, row in df.iterrows()
                if not __import__("math").isnan(row[col])
            ]

        return jsonify({
            "candles": candles,
            "indicators": indicators,
            "signal": signal,
            "details": details,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/market/symbols", methods=["GET"])
def get_symbols():
    client = _get_client()
    if not client:
        return jsonify([])
    try:
        symbols = client.get_top_volume_symbols(limit=50)
        return jsonify(symbols)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/market/ticker/<symbol>", methods=["GET"])
def get_ticker(symbol):
    client = _get_client()
    if not client:
        return jsonify({"error": "Bybit API not configured"}), 500
    try:
        ticker = client.get_ticker(symbol.upper())
        return jsonify({
            "symbol": ticker.get("symbol"),
            "last_price": float(ticker.get("lastPrice", 0)),
            "bid": float(ticker.get("bid1Price", 0)),
            "ask": float(ticker.get("ask1Price", 0)),
            "volume_24h": float(ticker.get("volume24h", 0)),
            "turnover_24h": float(ticker.get("turnover24h", 0)),
            "price_change_pct": float(ticker.get("price24hPcnt", 0)) * 100,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Templates API
# ---------------------------------------------------------------------------

@app.route("/api/templates", methods=["GET"])
def list_templates():
    db = SessionLocal()
    try:
        templates = db.query(BotTemplate).all()
        return jsonify([t.to_dict() for t in templates])
    finally:
        db.close()


@app.route("/api/templates", methods=["POST"])
def create_template():
    data = request.json
    db = SessionLocal()
    try:
        template = BotTemplate(
            name=data.get("name", "Custom Template"),
            strategy=data.get("strategy", "rsi_ema"),
            trade_qty=float(data.get("trade_qty", 0.001)),
            leverage=int(data.get("leverage", 5)),
            take_profit_pct=float(data.get("take_profit_pct", 2.0)),
            stop_loss_pct=float(data.get("stop_loss_pct", 1.0)),
            rsi_period=int(data.get("rsi_period", 14)),
            rsi_overbought=float(data.get("rsi_overbought", 70)),
            rsi_oversold=float(data.get("rsi_oversold", 30)),
            ema_fast=int(data.get("ema_fast", 9)),
            ema_slow=int(data.get("ema_slow", 21)),
            scan_interval=int(data.get("scan_interval", 60)),
        )
        db.add(template)
        db.commit()
        db.refresh(template)
        return jsonify(template.to_dict()), 201
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Wallet API
# ---------------------------------------------------------------------------

@app.route("/api/wallet", methods=["GET"])
def get_wallet():
    client = _get_client()
    if not client:
        return jsonify({"error": "Bybit API not configured"}), 500
    try:
        balance = client.get_wallet_balance()
        coins = balance.get("coin", [])
        usdt = next((c for c in coins if c["coin"] == "USDT"), None)
        if usdt:
            return jsonify({
                "balance": float(usdt.get("walletBalance", 0)),
                "available": float(usdt.get("availableToWithdraw", 0)),
                "equity": float(usdt.get("equity", 0)),
                "unrealised_pnl": float(usdt.get("unrealisedPnl", 0)),
            })
        return jsonify({"balance": 0, "available": 0, "equity": 0, "unrealised_pnl": 0})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def create_app():
    init_db()
    return app


if __name__ == "__main__":
    init_db()
    socketio.run(app, host="0.0.0.0", port=5000, debug=True)
