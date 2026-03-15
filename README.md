# Bybit Trading Bot

Automated trading bot that scans the market for profitable positions and executes trades on Bybit (testnet or mainnet). Optionally integrates with OpenClaw AI agent for signal validation.

## Strategy

- **RSI + EMA Crossover** with volume confirmation
- Scans top 20 USDT perpetuals by 24h volume
- Scores opportunities and trades the best ones
- Built-in TP/SL risk management

## Setup

```bash
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your Bybit testnet API keys
```

Get testnet API keys at: https://testnet.bybit.com

## Usage

```bash
# Run the bot (continuous scanning + trading)
python bot.py

# One-time market scan (no trades)
python bot.py --scan

# View open positions
python bot.py --positions

# Close all positions
python bot.py --close-all
```

## Configuration

All settings are in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `BYBIT_TESTNET` | `true` | Use testnet |
| `SYMBOL` | `BTCUSDT` | Default symbol |
| `TRADE_QTY` | `0.001` | Trade quantity |
| `LEVERAGE` | `5` | Leverage multiplier |
| `TAKE_PROFIT_PCT` | `2.0` | Take profit % |
| `STOP_LOSS_PCT` | `1.0` | Stop loss % |
| `RSI_PERIOD` | `14` | RSI lookback |
| `RSI_OVERSOLD` | `30` | RSI buy threshold |
| `RSI_OVERBOUGHT` | `70` | RSI sell threshold |
| `EMA_FAST` | `9` | Fast EMA period |
| `EMA_SLOW` | `21` | Slow EMA period |
| `SCAN_INTERVAL_SECONDS` | `60` | Scan frequency |

## OpenClaw Integration

Set `OPENCLAW_ENABLED=true` and configure `OPENCLAW_API_URL` and `OPENCLAW_API_KEY` in `.env`. When enabled, signals are validated through OpenClaw's AI before execution.

## Disclaimer

This bot is for educational and testnet use. Trading involves risk. Use at your own discretion.
