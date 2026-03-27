"""Tests for database models."""

import datetime
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import Base, Bot, Trade, BotTemplate


def _make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


class TestBotModel:
    def test_create_bot(self):
        s = _make_session()
        bot = Bot(name="Test Bot", symbol="BTCUSDT", status="stopped")
        s.add(bot)
        s.commit()
        assert bot.id is not None
        assert bot.symbol == "BTCUSDT"
        assert bot.leverage == 5  # default

    def test_bot_to_dict(self):
        s = _make_session()
        bot = Bot(name="Test", symbol="ETHUSDT", trade_qty=0.01, leverage=10)
        s.add(bot)
        s.commit()
        d = bot.to_dict()
        assert d["symbol"] == "ETHUSDT"
        assert d["trade_qty"] == 0.01
        assert d["leverage"] == 10
        assert "id" in d

    def test_bot_defaults(self):
        s = _make_session()
        bot = Bot(name="Defaults", symbol="BTCUSDT")
        s.add(bot)
        s.commit()
        assert bot.take_profit_pct == 2.0
        assert bot.stop_loss_pct == 1.0
        assert bot.rsi_period == 14
        assert bot.ema_fast == 9
        assert bot.ema_slow == 21


class TestTradeModel:
    def test_create_trade(self):
        s = _make_session()
        trade = Trade(symbol="BTCUSDT", side="Buy", qty=0.001, entry_price=50000)
        s.add(trade)
        s.commit()
        assert trade.id is not None
        assert trade.status == "open"

    def test_trade_to_dict(self):
        s = _make_session()
        trade = Trade(symbol="ETHUSDT", side="Sell", qty=0.1, signal_score=75.5)
        s.add(trade)
        s.commit()
        d = trade.to_dict()
        assert d["symbol"] == "ETHUSDT"
        assert d["side"] == "Sell"
        assert d["signal_score"] == 75.5


class TestBotTemplateModel:
    def test_create_template(self):
        s = _make_session()
        t = BotTemplate(name="Aggressive", leverage=10, trade_qty=0.01)
        s.add(t)
        s.commit()
        assert t.id is not None
        assert t.leverage == 10

    def test_template_to_dict(self):
        s = _make_session()
        t = BotTemplate(name="Conservative", leverage=2)
        s.add(t)
        s.commit()
        d = t.to_dict()
        assert d["name"] == "Conservative"
        assert d["leverage"] == 2
