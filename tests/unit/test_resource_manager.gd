## The single resource transaction (SPEC 5.3): check non-negative, check
## affordable, deduct once. A failed check changes nothing.
extends GutTest


func _bank(wood: int, gold: int) -> ResourceManager:
	return ResourceManager.new({"player": {"wood": wood, "gold": gold}, "ai": {"wood": 0, "gold": 0}})


func test_ac_32_spend_deducts_each_resource_once() -> void:
	var b: ResourceManager = _bank(100, 100)
	assert_eq(b.spend("player", {"wood": 60, "gold": 20}), "ok")
	assert_eq(b.stock.player, {"wood": 40, "gold": 80})
	assert_eq(b.spent.player, {"wood": 60, "gold": 20})


func test_ac_32_unaffordable_changes_nothing() -> void:
	var b: ResourceManager = _bank(40, 80)
	assert_eq(b.spend("player", {"wood": 60, "gold": 20}), "insufficient_resources")
	assert_eq(b.stock.player, {"wood": 40, "gold": 80})
	assert_eq(b.spent.player, {"wood": 0, "gold": 0})
	# Enough gold but not enough wood: still nothing is deducted.
	assert_eq(b.spend("player", {"wood": 41, "gold": 1}), "insufficient_resources")
	assert_eq(b.stock.player, {"wood": 40, "gold": 80})


func test_ac_32_exactly_affordable_leaves_zero() -> void:
	var b: ResourceManager = _bank(120, 60)
	assert_eq(b.spend("player", {"wood": 120, "gold": 60}), "ok")
	assert_eq(b.stock.player, {"wood": 0, "gold": 0})


func test_ac_20_negative_amount_is_invalid_and_changes_nothing() -> void:
	var b: ResourceManager = _bank(100, 100)
	assert_eq(b.spend("player", {"wood": -10, "gold": 0}), "invalid_amount")
	assert_eq(b.spend("player", {"wood": 10, "gold": -1}), "invalid_amount")
	assert_eq(b.spend("player", {"stone": 5}), "invalid_amount", "unknown resource")
	assert_eq(b.stock.player, {"wood": 100, "gold": 100})


func test_ac_33_refund_adds_back_and_is_recorded() -> void:
	var b: ResourceManager = _bank(200, 0)
	assert_eq(b.spend("player", {"wood": 50, "gold": 0}), "ok")
	b.refund("player", {"wood": 50, "gold": 0})
	assert_eq(b.stock.player.wood, 200)
	assert_eq(b.refunded.player.wood, 50)


func test_ac_07_ledger_balances() -> void:
	var b: ResourceManager = _bank(200, 100)
	b.spend("player", {"wood": 120, "gold": 60})
	b.deposit("player", "wood", 30)
	b.refund("player", {"wood": 50, "gold": 0})
	# 200 + 30 deposited + 50 refunded - 120 spent = 160; gold 100 - 60 = 40.
	assert_eq(b.stock.player, {"wood": 160, "gold": 40})
	assert_true(b.balanced("player"))
