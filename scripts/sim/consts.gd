## Simulation-wide constants from SPEC section 4.
## Unit and building stats live in data/units.json (decision D-11), not here.
class_name Consts
extends RefCounted

const TICKS_PER_SECOND: int = 20
const MILLI_PER_CELL: int = 1000
const PIXELS_PER_CELL: int = 32

const START_WOOD: int = 200
const START_GOLD: int = 100
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
