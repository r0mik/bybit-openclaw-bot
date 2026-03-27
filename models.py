"""Database models for the trading bot web UI."""

import datetime
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, JSON
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = "sqlite:///trading_bot.db"

engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class Bot(Base):
    __tablename__ = "bots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    symbol = Column(String(20), nullable=False)
    status = Column(String(20), default="stopped")  # running, stopped, error
    strategy = Column(String(50), default="rsi_ema")
    side = Column(String(10), nullable=True)  # Buy, Sell, or null (auto)
    trade_qty = Column(Float, default=0.001)
    leverage = Column(Integer, default=5)
    take_profit_pct = Column(Float, default=2.0)
    stop_loss_pct = Column(Float, default=1.0)
    rsi_period = Column(Integer, default=14)
    rsi_overbought = Column(Float, default=70)
    rsi_oversold = Column(Float, default=30)
    ema_fast = Column(Integer, default=9)
    ema_slow = Column(Integer, default=21)
    scan_interval = Column(Integer, default=60)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)
    error_message = Column(Text, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "symbol": self.symbol,
            "status": self.status,
            "strategy": self.strategy,
            "side": self.side,
            "trade_qty": self.trade_qty,
            "leverage": self.leverage,
            "take_profit_pct": self.take_profit_pct,
            "stop_loss_pct": self.stop_loss_pct,
            "rsi_period": self.rsi_period,
            "rsi_overbought": self.rsi_overbought,
            "rsi_oversold": self.rsi_oversold,
            "ema_fast": self.ema_fast,
            "ema_slow": self.ema_slow,
            "scan_interval": self.scan_interval,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "error_message": self.error_message,
        }


class Trade(Base):
    __tablename__ = "trades"

    id = Column(Integer, primary_key=True, autoincrement=True)
    bot_id = Column(Integer, nullable=True)
    symbol = Column(String(20), nullable=False)
    side = Column(String(10), nullable=False)
    qty = Column(Float, nullable=False)
    entry_price = Column(Float, nullable=True)
    exit_price = Column(Float, nullable=True)
    pnl = Column(Float, nullable=True)
    status = Column(String(20), default="open")  # open, closed, cancelled
    order_id = Column(String(100), nullable=True)
    take_profit = Column(Float, nullable=True)
    stop_loss = Column(Float, nullable=True)
    signal_score = Column(Float, nullable=True)
    signal_details = Column(JSON, nullable=True)
    opened_at = Column(DateTime, default=datetime.datetime.utcnow)
    closed_at = Column(DateTime, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "bot_id": self.bot_id,
            "symbol": self.symbol,
            "side": self.side,
            "qty": self.qty,
            "entry_price": self.entry_price,
            "exit_price": self.exit_price,
            "pnl": self.pnl,
            "status": self.status,
            "order_id": self.order_id,
            "take_profit": self.take_profit,
            "stop_loss": self.stop_loss,
            "signal_score": self.signal_score,
            "signal_details": self.signal_details,
            "opened_at": self.opened_at.isoformat() if self.opened_at else None,
            "closed_at": self.closed_at.isoformat() if self.closed_at else None,
        }


class BotTemplate(Base):
    __tablename__ = "bot_templates"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    strategy = Column(String(50), default="rsi_ema")
    trade_qty = Column(Float, default=0.001)
    leverage = Column(Integer, default=5)
    take_profit_pct = Column(Float, default=2.0)
    stop_loss_pct = Column(Float, default=1.0)
    rsi_period = Column(Integer, default=14)
    rsi_overbought = Column(Float, default=70)
    rsi_oversold = Column(Float, default=30)
    ema_fast = Column(Integer, default=9)
    ema_slow = Column(Integer, default=21)
    scan_interval = Column(Integer, default=60)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "strategy": self.strategy,
            "trade_qty": self.trade_qty,
            "leverage": self.leverage,
            "take_profit_pct": self.take_profit_pct,
            "stop_loss_pct": self.stop_loss_pct,
            "rsi_period": self.rsi_period,
            "rsi_overbought": self.rsi_overbought,
            "rsi_oversold": self.rsi_oversold,
            "ema_fast": self.ema_fast,
            "ema_slow": self.ema_slow,
            "scan_interval": self.scan_interval,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


def init_db():
    """Create all tables and seed default templates."""
    Base.metadata.create_all(engine)

    session = SessionLocal()
    if session.query(BotTemplate).count() == 0:
        defaults = [
            BotTemplate(name="Conservative", trade_qty=0.001, leverage=2,
                        take_profit_pct=1.5, stop_loss_pct=0.5, rsi_period=14,
                        rsi_overbought=75, rsi_oversold=25, ema_fast=9, ema_slow=21),
            BotTemplate(name="Balanced", trade_qty=0.005, leverage=5,
                        take_profit_pct=2.0, stop_loss_pct=1.0, rsi_period=14,
                        rsi_overbought=70, rsi_oversold=30, ema_fast=9, ema_slow=21),
            BotTemplate(name="Aggressive", trade_qty=0.01, leverage=10,
                        take_profit_pct=3.0, stop_loss_pct=1.5, rsi_period=7,
                        rsi_overbought=65, rsi_oversold=35, ema_fast=5, ema_slow=13),
        ]
        session.add_all(defaults)
        session.commit()
    session.close()


if __name__ == "__main__":
    init_db()
    print("Database initialized.")
