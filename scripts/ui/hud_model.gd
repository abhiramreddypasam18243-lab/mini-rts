## The data the HUD shows, read straight from the simulation each frame
## (presentation layer; read-only). Kept apart from drawing so it can be
## tested headless (AC-35); the HUD scene itself arrives in build step 7.
class_name HudModel
extends RefCounted


## The stockpile of the same tick the simulation is on (AC-35).
static func resources(sim: Simulation, faction: String) -> Dictionary:
	return {"wood": sim.resources[faction].wood, "gold": sim.resources[faction].gold}
