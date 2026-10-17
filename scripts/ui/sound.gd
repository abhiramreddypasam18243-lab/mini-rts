## Sound effects and music (presentation layer, decision D-41). One node,
## owned by the app root, so music carries on between screens. Effects come
## from Kenney's CC0 audio packs; music is "Town Theme RPG" (calm) and
## "Battle Theme A" (fighting) by cynicmusic, CC0. The calm theme plays in
## the menu and in quiet moments; the battle theme fades in while fighting
## is seen and fades out a few seconds after it stops. M mutes everything;
## the choice is remembered.
class_name Sound
extends Node

const SFX: Dictionary = {
	"sword": ["kenney_impact/impactMetal_medium_000", "kenney_impact/impactMetal_medium_002", "kenney_impact/impactMetal_medium_004",
		"kenney_impact/impactPlate_light_000", "kenney_impact/impactPlate_light_002"],
	"bow": ["kenney_rpg/knifeSlice", "kenney_rpg/knifeSlice2"],
	"arrow_hit": ["kenney_impact/impactWood_light_000", "kenney_impact/impactWood_light_002", "kenney_impact/impactPunch_medium_001"],
	"death": ["kenney_impact/impactPunch_heavy_000", "kenney_impact/impactPunch_heavy_002", "kenney_impact/impactPunch_heavy_004"],
	"collapse": ["kenney_impact/impactWood_heavy_000", "kenney_impact/impactWood_heavy_002", "kenney_impact/impactPlank_medium_003"],
	"chop": ["kenney_rpg/chop"],
	"mine": ["kenney_impact/impactMining_000", "kenney_impact/impactMining_002", "kenney_impact/impactMining_004"],
	"hammer": ["kenney_impact/impactWood_medium_001", "kenney_impact/impactWood_medium_003"],
	"coins": ["kenney_rpg/handleCoins", "kenney_rpg/handleCoins2"],
	"click": ["kenney_interface/click_001"],
	"order": ["kenney_interface/select_001"],
	"confirm": ["kenney_interface/confirmation_001"],
	"error": ["kenney_interface/error_004"],
}
const MUSIC: Dictionary = {"calm": "music/TownTheme.mp3", "battle": "music/battleThemeA.mp3"}
const DIR: String = "res://assets/audio/"
const VOICES: int = 14
const MUSIC_DB: float = -9.0
const SETTINGS: String = "user://settings.cfg"
## A sound of the same group plays at most this often (seconds).
const GAP: float = 0.05

static var instance: Sound

var muted: bool = false
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}
var _last: Dictionary = {}
var _music: Dictionary = {}
var _want: String = "calm"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0


func _ready() -> void:
	instance = self
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in VOICES:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for key: String in MUSIC:
		var m: AudioStreamPlayer = AudioStreamPlayer.new()
		var stream: AudioStream = load(DIR + MUSIC[key])
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		m.stream = stream
		m.volume_db = -80.0
		add_child(m)
		_music[key] = m
		# Both tracks run all the time; switching is only a volume change,
		# so no decoder starts in the middle of a battle.
		m.play()
	# Load every effect now, so the first clash of a battle does not stall
	# while a file loads.
	for group: String in SFX:
		for name: String in SFX[group]:
			_streams[name] = load(DIR + name + ".ogg")
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
	_apply_mute()


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Plays a sound from a group. `volume_db` 0 is full volume.
static func play(group: String, volume_db: float = 0.0, pitch_spread: float = 0.08) -> void:
	if instance != null:
		instance._play(group, volume_db, pitch_spread)


## Plays a sound at a world position: quieter the further it is from
## `listener` (the camera centre), silent beyond about one screen away.
static func play_at(group: String, at: Vector2, listener: Vector2, volume_db: float = 0.0) -> void:
	var d: float = at.distance_to(listener)
	if d > 1000.0:
		return
	play(group, volume_db - 20.0 * clampf(d / 1000.0, 0.0, 1.0) * clampf(d / 1000.0, 0.0, 1.0) * 1.6)


## Chooses the music: "calm" or "battle" (cross-faded).
static func music(which: String) -> void:
	if instance != null:
		instance._want = which


static func toggle_mute() -> void:
	if instance != null:
		instance.muted = not instance.muted
		instance._apply_mute()
		var cfg: ConfigFile = ConfigFile.new()
		cfg.set_value("audio", "muted", instance.muted)
		cfg.save(SETTINGS)


static func is_muted() -> bool:
	return instance != null and instance.muted


func _play(group: String, volume_db: float, pitch_spread: float) -> void:
	if muted or not SFX.has(group):
		return
	if _time - float(_last.get(group, -1.0)) < GAP:
		return
	_last[group] = _time
	var list: Array = SFX[group]
	var name: String = list[_rng.randi_range(0, list.size() - 1)]
	if not _streams.has(name):
		_streams[name] = load(DIR + name + ".ogg")
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	p.play()


func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


func _process(delta: float) -> void:
	_time += delta
	for key: String in _music:
		var m: AudioStreamPlayer = _music[key]
		var target: float = MUSIC_DB if key == _want else -60.0
		m.volume_db = move_toward(m.volume_db, target, delta * (24.0 if key == _want else 14.0))
		if not m.playing:
			m.play()


func _unhandled_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()
