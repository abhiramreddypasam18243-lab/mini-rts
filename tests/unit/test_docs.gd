## AC-88, AC-90 to AC-92, AC-94 to AC-96: the documents exist and contain
## what the spec asks for, and the test plan stays in step with the tests.
extends GutTest


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "%s exists" % path)
	return text


func test_ac_88_readme_has_every_required_part() -> void:
	var r: String = _read("res://README.md")
	for part: String in ["## Controls", "## How it is built", "| Entity | Wood | Gold | Health",
			"## How the enemy AI thinks", "## The strategy experiment", "## Known limitations",
			"## Setup from a clean checkout", "## Deployment"]:
		assert_string_contains(r, part)


func test_ac_90_readme_has_a_balance_log() -> void:
	var r: String = _read("res://README.md")
	assert_string_contains(r, "### Balance log")


func test_ac_91_architecture_shows_both_layers_and_rule_owners() -> void:
	var a: String = _read("res://docs/architecture.md")
	for part: String in ["Simulation core", "Presentation", "Which module owns each rule", "resource_manager.gd", "enemy_ai.gd"]:
		assert_string_contains(a, part)


func test_ac_92_test_plan_lists_every_ac_and_every_test() -> void:
	var plan: String = _read("res://docs/test-plan.md")
	for n: int in range(1, 97):
		assert_string_contains(plan, "| AC-%02d |" % n, "AC-%02d has a row" % n)
	# Every acceptance test in the suite appears in the plan.
	var dir: DirAccess = DirAccess.open("res://tests/unit")
	var re: RegEx = RegEx.new()
	re.compile("func (test_ac_\\d+_\\w+)\\(")
	var count: int = 0
	for f: String in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string("res://tests/unit".path_join(f))):
			count += 1
			assert_string_contains(plan, m.get_string(1), "%s is in the test plan" % m.get_string(1))
	assert_gt(count, 100)


func test_ac_94_readme_explains_astar_and_the_fsm_with_worked_examples() -> void:
	var r: String = _read("res://README.md")
	assert_string_contains(r, "## How A* finds paths")
	assert_string_contains(r, "Worked example (AC-13)")
	assert_string_contains(r, "27 steps")
	assert_string_contains(r, "Worked example (AC-62)")
	assert_string_contains(r, "240")


func test_ac_95_readme_states_the_v1_simplifications() -> void:
	var r: String = _read("res://README.md")
	for part: String in ["Pathfinding ignores fog", "Units share cells", "No line of sight", "Finite resource nodes"]:
		assert_string_contains(r, part)


func test_ac_96_every_decision_has_a_date_and_a_reason() -> void:
	var spec: String = _read("res://SPEC.md")
	var re: RegEx = RegEx.new()
	re.compile("(?m)^\\| D-(\\d+) \\| (\\d{4}-\\d{2}-\\d{2}) \\|([^|]*)\\|([^|]*)\\|([^|]*)\\|")
	var ids: Array[int] = []
	for m: RegExMatch in re.search_all(spec):
		ids.append(int(m.get_string(1)))
		assert_gt(m.get_string(3).strip_edges().length(), 10, "D-%s has a decision" % m.get_string(1))
		assert_gt(m.get_string(5).strip_edges().length(), 10, "D-%s has a reason" % m.get_string(1))
	ids.sort()
	var expected: Array[int] = []
	for i: int in range(1, ids.size() + 1):
		expected.append(i)
	assert_eq(ids, expected, "decisions D-01 to D-%02d, none missing" % ids.size())
