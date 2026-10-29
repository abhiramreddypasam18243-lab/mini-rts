## The How to play page (AC-75, controls of SPEC 9): it opens over the menu,
## fits on the screen (it was pushed off the bottom once the menu grew), and
## lists the keys the game uses.
extends GutTest


func test_ac_75_how_to_play_fits_the_screen_and_lists_the_controls() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await wait_frames(3)
	var menu: MainMenu = main.menu
	assert_false(menu.is_help_showing())
	menu.show_help()
	await wait_frames(3)
	assert_true(menu.is_help_showing())
	var screen: Rect2 = menu.get_viewport_rect()
	var panel: Control = menu._help.get_child(0).get_child(0)
	assert_true(screen.encloses(panel.get_global_rect()), "the whole page is on screen: %s in %s" % [panel.get_global_rect(), screen])
	var keys: String = ""
	for r: Array in MainMenu.help_rows(false):
		keys += str(r[0]) + " | "
	for k: String in ["B / N / T / V", "Q / W / E", "C", "R / Y", "F, then click", "Shift", "G", "K", "Space", "Mouse wheel", "Ctrl + A", "Esc"]:
		assert_string_contains(keys, k)


func test_the_menu_version_matches_the_windows_build_version() -> void:
	# The version printed in the menu must be the one the release carries,
	# so a player can tell whether a cached copy is old.
	var cfg: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var m: RegExMatch = RegEx.create_from_string('application/product_version="([0-9.]+)"').search(cfg)
	assert_not_null(m)
	assert_eq(MainMenu.version() + ".0", m.get_string(1))
