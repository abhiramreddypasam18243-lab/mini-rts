## Builders for the six commands of SPEC 6.2. The UI, the AI and the tests all
## create commands here, so every command has the same shape:
##   {"faction": String, "command": String, "args": Dictionary}
## Cells are stored as [x, y] so a command survives a round trip through JSON.
class_name Commands
extends RefCounted


## `queue` (decision D-44): run this order after the units' current and
## already queued orders instead of replacing them (Shift in the UI).
static func move(faction: String, unit_ids: Array, cell: Vector2i, queue: bool = false) -> Dictionary:
	return _queued(_cmd(faction, "move", {"unit_ids": unit_ids.duplicate(), "cell": [cell.x, cell.y]}), queue)


## Attack-move (D-44): walk to `cell`, fighting enemies met on the way.
static func attack_move(faction: String, unit_ids: Array, cell: Vector2i, queue: bool = false) -> Dictionary:
	return _queued(_cmd(faction, "attack_move", {"unit_ids": unit_ids.duplicate(), "cell": [cell.x, cell.y]}), queue)


static func harvest(faction: String, unit_ids: Array, node_id: int, queue: bool = false) -> Dictionary:
	return _queued(_cmd(faction, "harvest", {"unit_ids": unit_ids.duplicate(), "node_id": node_id}), queue)


static func build(faction: String, worker_id: int, building_type: String, cell: Vector2i) -> Dictionary:
	return _cmd(faction, "build", {"worker_id": worker_id, "building_type": building_type, "cell": [cell.x, cell.y]})


static func attack(faction: String, unit_ids: Array, target_id: int, queue: bool = false) -> Dictionary:
	return _queued(_cmd(faction, "attack", {"unit_ids": unit_ids.duplicate(), "target_id": target_id}), queue)


static func train(faction: String, building_id: int, unit_type: String) -> Dictionary:
	return _cmd(faction, "train", {"building_id": building_id, "unit_type": unit_type})


static func cancel_train(faction: String, building_id: int, index: int) -> Dictionary:
	return _cmd(faction, "cancel_train", {"building_id": building_id, "index": index})


## Adds "queue": true only when queued, so plain commands keep their shape.
static func _queued(cmd: Dictionary, queue: bool) -> Dictionary:
	if queue:
		cmd.args["queue"] = true
	return cmd


static func _cmd(faction: String, name: String, args: Dictionary) -> Dictionary:
	return {"faction": faction, "command": name, "args": args}
