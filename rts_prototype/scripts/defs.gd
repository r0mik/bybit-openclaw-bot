extends RefCounted
## Static game data: unit and building stats.

const UNITS := {
	"worker": {
		"name": "SCV (рабочий)", "hp": 45, "speed": 120.0, "radius": 9.0,
		"damage": 5, "range": 6.0, "cooldown": 1.5, "sight": 160.0,
		"cost": 50, "supply": 1, "time": 12.0, "hotkey": KEY_Q, "anti_air": false,
	},
	"marine": {
		"name": "Marine (пехотинец)", "hp": 45, "speed": 105.0, "radius": 10.0,
		"damage": 6, "range": 130.0, "cooldown": 0.65, "sight": 240.0,
		"cost": 50, "supply": 1, "time": 14.0, "hotkey": KEY_Q,
	},
	"tank": {
		"name": "Siege Tank (танк)", "hp": 160, "speed": 75.0, "radius": 16.0,
		"damage": 30, "range": 240.0, "cooldown": 2.2, "sight": 300.0, "splash": 40.0,
		"cost": 150, "supply": 3, "time": 25.0, "hotkey": KEY_T, "anti_air": false,
	},
	"wraith": {
		"name": "Wraith (истребитель)", "hp": 120, "speed": 150.0, "radius": 13.0,
		"damage": 10, "range": 150.0, "cooldown": 1.1, "sight": 280.0,
		"cost": 150, "supply": 2, "time": 28.0, "hotkey": KEY_W, "air": true,
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
	"bunker": {
		"name": "Bunker", "short": "BUNKER", "hp": 550, "size": Vector2(80, 64),
		"cost": 100, "time": 25.0, "trains": [], "hotkey": KEY_U, "requires": "barracks",
		"damage": 7, "range": 150.0, "cooldown": 0.45,
	},
	"ebay": {
		"name": "Engineering Bay", "short": "ENG BAY", "hp": 850, "size": Vector2(100, 80),
		"cost": 125, "time": 35.0, "trains": [], "research": ["weapons", "armor"], "hotkey": KEY_E,
	},
	"turret": {
		"name": "Missile Turret", "short": "TURRET", "hp": 300, "size": Vector2(50, 50),
		"cost": 100, "time": 20.0, "trains": [], "hotkey": KEY_T, "requires": "ebay",
		"damage": 12, "range": 230.0, "cooldown": 0.85, "air_bonus": 2.0,
	},
	"starport": {
		"name": "Starport", "short": "STARPORT", "hp": 1300, "size": Vector2(120, 100),
		"cost": 200, "time": 50.0, "trains": ["wraith"], "hotkey": KEY_P, "requires": "factory",
	},
}

## Team-wide research done in the Engineering Bay.
const UPGRADES := {
	"weapons": {"name": "Оружие", "cost": [100, 175], "time": 40.0, "hotkey": KEY_W, "max": 2},
	"armor": {"name": "Броня", "cost": [100, 175], "time": 40.0, "hotkey": KEY_R, "max": 2},
}

const WORKER_BUILDS := ["depot", "barracks", "bunker", "ebay", "turret", "factory", "starport", "cc"]
const MAX_SUPPLY := 200
