## One faction's view of the world (SPEC 7.2). The AI decides from this alone.
##
## It holds plain copies, never references to simulation objects, so nothing
## the AI does with it can change the game, and nothing hidden is inside it:
##   - the tick, the faction's resources and the public stats table;
##   - its own units and buildings (with their queues);
##   - enemy units standing on cells it can see now;
##   - remembered enemy buildings ("ghosts") and resource nodes, as last seen;
##   - the terrain, the possible start positions and its own fog grid.
## Entities are snapshots: {"id", "kind", "faction", "cell", "pos", "hp", ...}.
class_name Observation
extends RefCounted

var tick: int
var faction: String
var resources: Dictionary
var own_units: Array[Dictionary] = []
var own_buildings: Array[Dictionary] = []
var enemy_units: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var nodes: Array[Dictionary] = []
var width: int
var height: int
## 1 = blocked terrain; index y * width + x.
var terrain: PackedByteArray
var possible_starts: Array[Vector2i] = []
## Fog states (Fog.UNEXPLORED / EXPLORED / VISIBLE); index y * width + x.
var fog: PackedByteArray
var stats: Dictionary
## The faction's researched upgrades: name -> true (D-51).
var upgrades: Dictionary = {}


## Every entity id this observation contains: the only ids the AI may name
## in its commands (the firewall check, build step 8).
func known_ids() -> Dictionary:
	var out: Dictionary = {}
	for list: Array[Dictionary] in [own_units, own_buildings, enemy_units, ghosts, nodes]:
		for d: Dictionary in list:
			out[d.id] = true
	return out
