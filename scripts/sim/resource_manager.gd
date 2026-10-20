## Stockpiles and the one resource transaction (SPEC 5.3; AC-07, AC-32, AC-33).
##
## Every purchase in the game calls spend(), which does, in this order:
##   1. check every amount is a whole number >= 0 and names a resource
##      -> otherwise "invalid_amount";
##   2. check the faction can afford every resource
##      -> otherwise "insufficient_resources";
##   3. deduct all resources at once and record the spend.
## A failed check returns before anything changes. The caller validates its
## own rules first and acts only after spend() returns "ok", so a purchase is
## never half-done.
##
## The ledger (deposited, spent, refunded, removed from nodes, lost when a
## carrying worker dies) lets the tests
## check conservation: stock == start + deposited + refunded - spent.
class_name ResourceManager
extends RefCounted

## Wood, gold and food (D-51). A bank holds the resources its start names
## (the simulation passes all three).
const TYPES: Array[String] = ["wood", "gold", "food"]

## The resources this bank holds, in TYPES order.
var types: Array[String] = []
## Faction -> {"wood": int, "gold": int, "food": int}.
var stock: Dictionary = {}
var start: Dictionary = {}
var deposited: Dictionary = {}
var spent: Dictionary = {}
var refunded: Dictionary = {}
## Taken out of resource nodes by this faction's workers.
var removed: Dictionary = {}
## Carried by workers that died before depositing.
var lost: Dictionary = {}


func _init(p_start: Dictionary) -> void:
	for r: String in TYPES:
		for f: String in p_start:
			if (p_start[f] as Dictionary).has(r) and not r in types:
				types.append(r)
	for f: String in p_start:
		stock[f] = (p_start[f] as Dictionary).duplicate()
		start[f] = (p_start[f] as Dictionary).duplicate()
		deposited[f] = _zero()
		spent[f] = _zero()
		refunded[f] = _zero()
		removed[f] = _zero()
		lost[f] = _zero()


func _zero() -> Dictionary:
	var z: Dictionary = {}
	for r: String in types:
		z[r] = 0
	return z


## Returns "ok", "invalid_amount" or "insufficient_resources" without changing anything.
func check(faction: String, cost: Dictionary) -> String:
	for r: Variant in cost:
		if not r in types or not JsonUtil.is_whole(cost[r]) or int(cost[r]) < 0:
			return "invalid_amount"
	for r: Variant in cost:
		if stock[faction][r] < int(cost[r]):
			return "insufficient_resources"
	return "ok"


## The transaction: check, then deduct once.
func spend(faction: String, cost: Dictionary) -> String:
	var result: String = check(faction, cost)
	if result != "ok":
		return result
	for r: Variant in cost:
		stock[faction][r] -= int(cost[r])
		spent[faction][r] += int(cost[r])
	return "ok"


## Gives back a cost paid earlier (cancelled production). The caller removes
## the item it refunds, so each item can be refunded only once.
func refund(faction: String, cost: Dictionary) -> void:
	for r: Variant in cost:
		stock[faction][r] += int(cost[r])
		refunded[faction][r] += int(cost[r])


func deposit(faction: String, type: String, amount: int) -> void:
	stock[faction][type] += amount
	deposited[faction][type] += amount


func record_removed(faction: String, type: String, amount: int) -> void:
	removed[faction][type] += amount


func record_lost(faction: String, type: String, amount: int) -> void:
	lost[faction][type] += amount


## stock == start + deposited + refunded - spent, for every resource.
func balanced(faction: String) -> bool:
	for r: String in types:
		if stock[faction][r] != start[faction][r] + deposited[faction][r] + refunded[faction][r] - spent[faction][r]:
			return false
	return true


func add_to_hash(h: StateHasher) -> void:
	for f: String in Consts.FACTIONS:
		for r: String in types:
			h.add_int(stock[f][r])
			h.add_int(deposited[f][r])
			h.add_int(spent[f][r])
			h.add_int(refunded[f][r])
			h.add_int(removed[f][r])
			h.add_int(lost[f][r])
