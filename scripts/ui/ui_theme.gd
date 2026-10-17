## The UI look (presentation layer): wooden frames, parchment insets and
## game buttons from Kenney's CC0 "UI Pack: RPG Expansion", with Cinzel for
## titles and Alegreya Sans for text (both SIL OFL; see ASSETS.md).
class_name UiTheme
extends RefCounted

const FONT_PATHS: Dictionary = {
	"regular": "res://assets/fonts/AlegreyaSans-Regular.ttf",
	"semibold": "res://assets/fonts/AlegreyaSans-Medium.ttf",
	"bold": "res://assets/fonts/AlegreyaSans-Bold.ttf",
	"title": "res://assets/fonts/Cinzel-Variable.ttf",
}
const UI: String = "res://assets/kenney/ui_rpg/"

static var _fonts: Dictionary = {}
static var _theme: Theme = null
static var _tex: Dictionary = {}


static func font(weight: String = "regular") -> Font:
	if not _fonts.has(weight):
		var f: Font = load(FONT_PATHS[weight]) as Font
		if weight == "title" and f != null:
			var v: FontVariation = FontVariation.new()
			v.base_font = f
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
			f = v
		_fonts[weight] = f if f != null else ThemeDB.fallback_font
	return _fonts[weight]


## A font with extra space between letters, for titles.
static func spaced(weight: String, spacing: int) -> FontVariation:
	var v: FontVariation = FontVariation.new()
	v.base_font = font(weight)
	v.spacing_glyph = spacing
	return v


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(UI + name + ".png")
	return _tex[name]


## A 9-slice style from a UI-pack texture.
static func frame(name: String, margin: int, pad: Vector2 = Vector2(14, 10), modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var s: StyleBoxTexture = StyleBoxTexture.new()
	s.texture = tex(name)
	s.set_texture_margin_all(margin)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.modulate_color = modulate
	return s


## The wooden frame used for HUD panels and dialogs.
static func panel_box(pad: Vector2 = Vector2(18, 16)) -> StyleBoxTexture:
	return frame("panel_brown", 18, pad)


## A parchment inset, for content inside a wooden frame.
static func parchment(pad: Vector2 = Vector2(12, 10)) -> StyleBoxTexture:
	return frame("panelInset_beige", 16, pad)


static func box(bg: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0,
		pad: Vector2 = Vector2(14, 10), shadow: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 4)
	return s


## Button styles: parchment ("beige"), gold (the main action: parchment
## tinted gold) or brown.
static func style_button(b: Button, colour: String = "beige", font_size: int = 17) -> void:
	var pad: Vector2 = Vector2(16, 8)
	var tex_name: String = "beige" if colour == "gold" else colour
	var tint: Color = Color(1.0, 0.82, 0.38) if colour == "gold" else Color.WHITE
	b.add_theme_stylebox_override("normal", frame("buttonLong_" + tex_name, 12, pad, tint * Color(0.95, 0.93, 0.9)))
	b.add_theme_stylebox_override("hover", frame("buttonLong_" + tex_name, 12, pad, tint))
	b.add_theme_stylebox_override("pressed", frame("buttonLong_%s_pressed" % tex_name, 12, pad, tint))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", frame("buttonLong_grey", 12, pad, Color(1, 1, 1, 0.6)))
	var ink: Color = Palette.TEXT if colour == "brown" else Palette.INK
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink)
	b.add_theme_color_override("font_pressed_color", ink)
	b.add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.28))
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func() -> void: Sound.play("click", -6.0, 0.0))


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 16
	var pad: Vector2 = Vector2(14, 8)
	t.set_stylebox("normal", "Button", frame("buttonLong_beige", 12, pad, Color(0.94, 0.92, 0.88)))
	t.set_stylebox("hover", "Button", frame("buttonLong_beige", 12, pad))
	t.set_stylebox("pressed", "Button", frame("buttonLong_beige_pressed", 12, pad))
	t.set_stylebox("disabled", "Button", frame("buttonLong_grey", 12, pad, Color(1, 1, 1, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Palette.INK)
	t.set_color("font_hover_color", "Button", Palette.INK)
	t.set_color("font_pressed_color", "Button", Palette.INK)
	t.set_color("font_disabled_color", "Button", Color(0.25, 0.25, 0.28))
	t.set_font("font", "Button", font("bold"))
	for k: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(k, "OptionButton", t.get_stylebox(k, "Button"))
	t.set_color("font_color", "OptionButton", Palette.INK)
	t.set_color("font_hover_color", "OptionButton", Palette.INK)
	t.set_font("font", "OptionButton", font("bold"))
	t.set_stylebox("panel", "PopupMenu", frame("panel_beigeLight", 16, Vector2(6, 6)))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.24, 0.55, 0.84, 0.35), 6, Color(0, 0, 0, 0), 0, Vector2(8, 4)))
	t.set_color("font_color", "PopupMenu", Palette.INK)
	t.set_color("font_hover_color", "PopupMenu", Palette.INK)
	t.set_font("font", "PopupMenu", font("semibold"))
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_stylebox("normal", "LineEdit", frame("panelInset_beige", 14, Vector2(10, 6)))
	t.set_stylebox("focus", "LineEdit", frame("panelInset_beige", 14, Vector2(10, 6)))
	t.set_color("font_color", "LineEdit", Palette.INK)
	t.set_color("caret_color", "LineEdit", Palette.INK)
	t.set_font("font", "LineEdit", font("bold"))
	t.set_stylebox("panel", "TooltipPanel", frame("panel_beigeLight", 14, Vector2(10, 7)))
	t.set_color("font_color", "TooltipLabel", Palette.INK)
	t.set_font("font", "TooltipLabel", font("semibold"))
	t.set_font_size("font_size", "TooltipLabel", 15)
	_theme = t
	return t


## A label with a given weight, size and colour.
static func label(text: String, size: int = 16, weight: String = "regular", color: Color = Palette.TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
