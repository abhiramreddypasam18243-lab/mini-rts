## AC-85 (rules L1, L2): every file in assets/ is listed in ASSETS.md with a
## source and a licence. Runs in CI with the rest of the suite, so a new
## asset without a licence record fails the build and blocks the deploy.
extends GutTest

const IGNORED_SUFFIXES: Array[String] = [".import", ".uid"]


func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		var skip: bool = false
		for s: String in IGNORED_SUFFIXES:
			skip = skip or f.ends_with(s)
		if not skip:
			out.append(dir_path.path_join(f).trim_prefix("res://"))
	for d: String in dir.get_directories():
		out.append_array(_files(dir_path.path_join(d)))
	return out


func test_ac_85_every_asset_is_listed_with_source_and_licence() -> void:
	var doc: String = FileAccess.get_file_as_string("res://ASSETS.md")
	var files: Array[String] = _files("res://assets")
	assert_gt(files.size(), 0, "found the asset files")
	for f: String in files:
		var row: String = ""
		for line: String in doc.split("\n"):
			if line.begins_with("|") and line.contains("`%s`" % f):
				row = line
		assert_ne(row, "", "%s is listed in ASSETS.md" % f)
		var cells: PackedStringArray = row.split("|")
		# | file | source | licence | notes |
		assert_true(cells.size() >= 5 and cells[2].strip_edges() != "" and cells[3].strip_edges() != "",
			"%s has a source and a licence" % f)


func test_ac_85_every_art_source_is_credited_in_the_game() -> void:
	# The Credits screen names every art, sound and font source in ASSETS.md.
	var text: String = MainMenu.credits_text()
	for source: String in ["Kay Lousberg", "Kenney", "ambientCG", "cynicmusic", "Cinzel", "Alegreya Sans", "Godot"]:
		assert_string_contains(text, source)
