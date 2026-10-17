## Every colour the game draws with, in one place (presentation layer).
## A dark "tactical board": slate ground, teal for the player, coral for the AI.
class_name Palette
extends RefCounted

const BG: Color = Color("0a0f15")
const GROUND: Color = Color("1a2430")
const GROUND_ALT: Color = Color("1c2633")
const GROUND_SPECK: Color = Color(1, 1, 1, 0.035)
const GRID: Color = Color(1, 1, 1, 0.025)
const MAP_EDGE: Color = Color("2c3a4b")

const ROCK: Color = Color("394352")
const ROCK_LIGHT: Color = Color("5a6578")
const ROCK_DARK: Color = Color("262d38")

const WOOD: Color = Color("3fbf7f")
const WOOD_DARK: Color = Color("1d6b47")
const WOOD_LIGHT: Color = Color("8ae6b2")
const TRUNK: Color = Color("6b4f3a")
const GOLD: Color = Color("f5b841")
const GOLD_DARK: Color = Color("9c6a17")
const GOLD_LIGHT: Color = Color("ffe49a")

const TEAM: Dictionary = {"player": Color("2ec4b6"), "ai": Color("ff6b6b"), "": Color("c9d3df")}
const TEAM_DARK: Dictionary = {"player": Color("135a54"), "ai": Color("7f2a35"), "": Color("4a5566")}
const TEAM_LIGHT: Dictionary = {"player": Color("9df3ea"), "ai": Color("ffc2c2"), "": Color("eef3f8")}

const FOG: Color = Color("05080c")
const SHADOW: Color = Color(0, 0, 0, 0.38)

const TEXT: Color = Color("e8eef5")
const MUTED: Color = Color("8d9bb0")
const FAINT: Color = Color("5c6b80")
const ACCENT: Color = Color("2ec4b6")
const PANEL: Color = Color(0.055, 0.08, 0.11, 0.86)
const PANEL_LIGHT: Color = Color(1, 1, 1, 0.05)
const PANEL_BORDER: Color = Color(1, 1, 1, 0.09)

const GOOD: Color = Color("4cd98a")
const BAD: Color = Color("ff5d6c")
const WARN: Color = Color("f5b841")


## Health bar colour: green, then amber, then red.
static func health(ratio: float) -> Color:
	if ratio > 0.6:
		return GOOD
	if ratio > 0.3:
		return WARN
	return BAD


static func resource(kind: String) -> Color:
	return WOOD if kind == "wood" else GOLD
