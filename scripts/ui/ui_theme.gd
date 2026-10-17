## The UI look: fonts (Chakra Petch, OFL; see ASSETS.md) and rounded,
## translucent panels and buttons, built in code (presentation layer).
class_name UiTheme
extends RefCounted

const FONT_PATHS: Dictionary = {
	"regular": "res://assets/fonts/ChakraPetch-Regular.ttf",
	"semibold": "res://assets/fonts/ChakraPetch-SemiBold.ttf",
	"bold": "res://assets/fonts/ChakraPetch-Bold.ttf",
}

static var _fonts: Dictionary = {}
static var _theme: Theme = null


static func font(weight: String = "regular") -> Font:
	if not _fonts.has(weight):
		var f: Font = load(FONT_PATHS[weight]) as Font
		_fonts[weight] = f if f != null else ThemeDB.fallback_font
	return _fonts[weight]


## A font with extra space between letters, for titles.
static func spaced(weight: String, spacing: int) -> FontVariation:
	var v: FontVariation = FontVariation.new()
	v.base_font = font(weight)
	v.spacing_glyph = spacing
	return v


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


static func panel_box() -> StyleBoxFlat:
	return box(Palette.PANEL, 14, Palette.PANEL_BORDER, 1, Vector2(16, 14), 18)


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 15
	# Buttons
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.055), 9, Color(1, 1, 1, 0.09), 1))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.10), 9, Color(Palette.ACCENT, 0.55), 1))
	t.set_stylebox("pressed", "Button", box(Color(Palette.ACCENT, 0.22), 9, Palette.ACCENT, 1))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.025), 9, Color(1, 1, 1, 0.05), 1))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 9, Color(Palette.ACCENT, 0.7), 1))
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Palette.FAINT)
	t.set_font("font", "Button", font("semibold"))
	# Panels and labels
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_color("font_color", "Label", Palette.TEXT)
	# Text fields
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.3), 8, Color(1, 1, 1, 0.1), 1, Vector2(10, 7)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.3), 8, Palette.ACCENT, 1, Vector2(10, 7)))
	t.set_color("font_color", "LineEdit", Palette.TEXT)
	t.set_color("caret_color", "LineEdit", Palette.ACCENT)
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", box(Color("101722"), 8, Color(1, 1, 1, 0.12), 1, Vector2(10, 7), 8))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	t.set_font("font", "TooltipLabel", font("regular"))
	t.set_font_size("font_size", "TooltipLabel", 14)
	_theme = t
	return t


## A label with a given weight, size and colour.
static func label(text: String, size: int = 15, weight: String = "regular", color: Color = Palette.TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
