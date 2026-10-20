## Every colour the game draws with, in one place (presentation layer).
## A warm medieval look to match the Kenney CC0 art (decision D-38): green
## fields, blue for the player, red for the AI, wood-and-parchment UI.
class_name Palette
extends RefCounted

const BG: Color = Color("1a140e")
const MAP_EDGE: Color = Color("5a3d24")
const MAP_EDGE_DARK: Color = Color("3a2716")

const WOOD: Color = Color("6fbf4a")
const GOLD: Color = Color("f2b632")
const FOOD: Color = Color("e8925a")

const TEAM: Dictionary = {"player": Color("3d8fd6"), "ai": Color("d84a3a"), "": Color("d9cfa8")}
const TEAM_DARK: Dictionary = {"player": Color("1d4f80"), "ai": Color("7c2219"), "": Color("6b5a3a")}
const TEAM_LIGHT: Dictionary = {"player": Color("9fd0ff"), "ai": Color("ffb3a8"), "": Color("fff4d6")}

const FOG: Color = Color("0e100b")

# UI: cream text on wood, dark ink on parchment, gold accents.
const TEXT: Color = Color("fbf1d9")
const MUTED: Color = Color("d8c39a")
const FAINT: Color = Color("a8916a")
const INK: Color = Color("3d2a19")
const INK_MUTED: Color = Color("7a5f42")
const ACCENT: Color = Color("f2b632")
const PANEL: Color = Color(0.36, 0.24, 0.14, 0.94)

const GOOD: Color = Color("62c24a")
const BAD: Color = Color("e0503e")
const WARN: Color = Color("f0a830")


## Health bar colour: green, then amber, then red.
static func health(ratio: float) -> Color:
	if ratio > 0.6:
		return GOOD
	if ratio > 0.3:
		return WARN
	return BAD


static func resource(kind: String) -> Color:
	return WOOD if kind == "wood" else (FOOD if kind == "food" or kind == "farm" else GOLD)
