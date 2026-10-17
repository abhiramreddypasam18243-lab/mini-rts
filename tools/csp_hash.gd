## Writes the nginx Content-Security-Policy for the exported page (SPEC D5;
## AC-82). The page has one inline <script> and one inline <style>; instead
## of allowing all inline code ('unsafe-inline'), the policy allows exactly
## those blocks by their SHA-256 hash. Run after every export:
##   godot --headless --script res://tools/csp_hash.gd -- build/web/index.html build/csp.conf
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: csp_hash.gd -- <index.html> <out.conf>")
		quit(1)
		return
	var html: String = FileAccess.get_file_as_string(args[0])
	var scripts: PackedStringArray = _inline_blocks(html, "script")
	var styles: PackedStringArray = _inline_blocks(html, "style")
	if scripts.is_empty():
		printerr("no inline <script> found in ", args[0])
		quit(1)
		return
	var policy: String = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' %s; style-src 'self' %s; img-src 'self' data: blob:; connect-src 'self' blob: data:; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'self'" % [
		" ".join(_hashes(scripts)), " ".join(_hashes(styles))]
	var f: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string("add_header Content-Security-Policy \"%s\" always;\n" % policy)
	f.close()
	print("CSP: %d script hash(es), %d style hash(es) -> %s" % [scripts.size(), styles.size(), args[1]])
	quit(0)


## Contents of <tag>...</tag> blocks without a src attribute, byte for byte.
func _inline_blocks(html: String, tag: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var re: RegEx = RegEx.new()
	re.compile("<%s(\\s[^>]*)?>([\\s\\S]*?)</%s>" % [tag, tag])
	for m: RegExMatch in re.search_all(html):
		if m.get_string(1).contains("src="):
			continue
		out.append(m.get_string(2))
	return out


func _hashes(blocks: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for b: String in blocks:
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(b.to_utf8_buffer())
		out.append("'sha256-%s'" % Marshalls.raw_to_base64(ctx.finish()))
	return out
