extends RefCounted
## Static game data: unit and building stats.

const UNITS := {
	"worker": {
		"name": "SCV (рабочий)", "hp": 45, "speed": 120.0, "radius": 9.0,
		"damage": 5, "range": 6.0, "cooldown": 1.5, "sight": 160.0,
		"cost": 50, "supply": 1, "time": 12.0, "hotkey": KEY_Q,
	},
	"marine": {
		"name": "Marine (пехотинец)", "hp": 45, "speed": 105.0, "radius": 10.0,
		"damage": 6, "range": 130.0, "cooldown": 0.65, "sight": 240.0,
		"cost": 50, "supply": 1, "time": 14.0, "hotkey": KEY_Q,
	},
	"tank": {
		"name": "Siege Tank (танк)", "hp": 160, "speed": 75.0, "radius": 16.0,
		"damage": 30, "range": 240.0, "cooldown": 2.2, "sight": 300.0, "splash": 40.0,
		"cost": 150, "supply": 3, "time": 25.0, "hotkey": KEY_T,
	},
}

const BUILDINGS := {
	"cc": {
		"name": "Command Center", "short": "COMMAND", "hp": 1500, "size": Vector2(130, 100),
		"cost": 400, "time": 70.0, "supply": 10, "trains": ["worker"], "hotkey": KEY_C,
	},
	"depot": {
		"name": "Supply Depot", "short": "DEPOT", "hp": 400, "size": Vector2(70, 70),
		"cost": 100, "time": 20.0, "supply": 8, "trains": [], "hotkey": KEY_D,
	},
	"barracks": {
		"name": "Barracks", "short": "BARRACKS", "hp": 1000, "size": Vector2(110, 90),
		"cost": 150, "time": 40.0, "trains": ["marine"], "hotkey": KEY_B,
	},
	"factory": {
		"name": "Factory", "short": "FACTORY", "hp": 1250, "size": Vector2(120, 90),
		"cost": 200, "time": 50.0, "trains": ["tank"], "hotkey": KEY_F, "requires": "barracks",
	},
}

const WORKER_BUILDS := ["depot", "barracks", "factory", "cc"]
const MAX_SUPPLY := 200
