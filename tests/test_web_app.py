"""Tests for the Flask web application."""

import json
import pytest
from unittest.mock import patch, MagicMock

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import Base, Bot, BotTemplate, SessionLocal
import models
import web_app


@pytest.fixture(autouse=True)
def setup_test_db(monkeypatch):
    """Use in-memory SQLite for every test."""
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    _Session = sessionmaker(bind=engine)
    monkeypatch.setattr(models, "SessionLocal", _Session)
    monkeypatch.setattr(web_app, "SessionLocal", _Session)
    # Seed a template
    s = _Session()
    s.add(BotTemplate(name="Test Template", leverage=3))
    s.commit()
    s.close()
    yield


@pytest.fixture
def client():
    web_app.app.config["TESTING"] = True
    with web_app.app.test_client() as c:
        yield c


class TestBotAPI:
    def test_list_bots_empty(self, client):
        resp = client.get("/api/bots")
        assert resp.status_code == 200
        assert resp.json == []

    def test_create_bot(self, client):
        resp = client.post("/api/bots", json={
            "name": "My Bot",
            "symbol": "ETHUSDT",
            "trade_qty": 0.05,
        })
        assert resp.status_code == 201
        data = resp.json
        assert data["symbol"] == "ETHUSDT"
        assert data["trade_qty"] == 0.05
        assert data["status"] == "stopped"

    def test_create_and_list(self, client):
        client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        client.post("/api/bots", json={"name": "B2", "symbol": "ETHUSDT"})
        resp = client.get("/api/bots")
        assert len(resp.json) == 2

    def test_filter_by_status(self, client):
        client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        resp = client.get("/api/bots?status=running")
        assert len(resp.json) == 0
        resp = client.get("/api/bots?status=stopped")
        assert len(resp.json) == 1

    def test_filter_by_symbol(self, client):
        client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        client.post("/api/bots", json={"name": "B2", "symbol": "ETHUSDT"})
        resp = client.get("/api/bots?symbol=ETH")
        assert len(resp.json) == 1
        assert resp.json[0]["symbol"] == "ETHUSDT"

    def test_get_bot(self, client):
        resp = client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        bot_id = resp.json["id"]
        resp = client.get(f"/api/bots/{bot_id}")
        assert resp.status_code == 200
        assert resp.json["name"] == "B1"

    def test_get_bot_not_found(self, client):
        resp = client.get("/api/bots/999")
        assert resp.status_code == 404

    def test_update_bot(self, client):
        resp = client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        bot_id = resp.json["id"]
        resp = client.put(f"/api/bots/{bot_id}", json={"leverage": 20})
        assert resp.status_code == 200
        assert resp.json["leverage"] == 20

    def test_delete_bot(self, client):
        resp = client.post("/api/bots", json={"name": "B1", "symbol": "BTCUSDT"})
        bot_id = resp.json["id"]
        resp = client.delete(f"/api/bots/{bot_id}")
        assert resp.status_code == 200
        resp = client.get("/api/bots")
        assert len(resp.json) == 0


class TestTemplatesAPI:
    def test_list_templates(self, client):
        resp = client.get("/api/templates")
        assert resp.status_code == 200
        assert len(resp.json) >= 1

    def test_create_template(self, client):
        resp = client.post("/api/templates", json={
            "name": "My Template",
            "leverage": 15,
        })
        assert resp.status_code == 201
        assert resp.json["name"] == "My Template"
        assert resp.json["leverage"] == 15


class TestTradesAPI:
    def test_list_trades_empty(self, client):
        resp = client.get("/api/trades")
        assert resp.status_code == 200
        assert resp.json == []


class TestPositionsAPI:
    @patch.object(web_app, '_get_client', return_value=None)
    def test_positions_no_client(self, mock_client, client):
        resp = client.get("/api/positions")
        assert resp.status_code == 200
        assert resp.json == []


class TestPageRoutes:
    def test_index_page(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        assert b"Bybit Trading Bot" in resp.data
