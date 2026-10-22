## Simulation-wide constants from SPEC section 4.
## Unit and building stats live in data/units.json (decision D-11), not here.
class_name Consts
extends RefCounted

const TICKS_PER_SECOND: int = 20
const MILLI_PER_CELL: int = 1000
const PIXELS_PER_CELL: int = 32

const START_WOOD: int = 200
const START_GOLD: int = 100
## Food (D-51): a third resource, gathered from farms.
const START_FOOD: int = 100
const FARM_FOOD: int = 400
## Upgrades researched at a barracks (D-51): cost and time.
const UPGRADES: Dictionary = {
	"forging": {"wood": 0, "gold": 80, "food": 100, "time": 400},
	"armour": {"wood": 0, "gold": 100, "food": 100, "time": 400},
}
## Forging adds this to a soldier's damage; Armour takes it off each hit.
const UPGRADE_BONUS: int = 2
## Cavalry charge (D-57): the first hit after galloping at least
## CHARGE_DIST milli-cells (3 cells) since the last hit deals double damage.
const CHARGE_DIST: int = 3000
const START_WORKERS: int = 3

const WOOD_NODE_AMOUNT: int = 500
const GOLD_NODE_AMOUNT: int = 300
const CARRY_CAPACITY: int = 10
const HARVEST_TICKS: int = 40

const QUEUE_CAPACITY: int = 5
const POPULATION_CAP: int = 40
const MAX_SELECTION: int = 24

const DEFAULT_MAP_SIZE: int = 48
const DEFAULT_MAX_TICKS: int = 36000
const AI_DECISION_INTERVAL: int = 10

const FACTIONS: Array[String] = ["player", "ai"]
