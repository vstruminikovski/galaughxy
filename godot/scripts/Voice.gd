class_name Voice
extends Node

## Dialogue audio for every character.
## DialogueBus = PitchShift -> BandPassFilter -> SpectrumAnalyzer. When a character speaks, its
## characters.json preset ({pitch, filter}) is applied to the bus, and the analyzer's energy in
## 200-3000 Hz drives that character's mouth, sampled 12 times a second (On Twos).
## Sources: an episode clip (.wav / .ogg under res://assets/audio/), or live test input: holding
## Talk plays a synthesized babble voice through the same chain. A line whose clip is not recorded
## yet lasts 0.065 s per character of its text and uses the procedural talk bounce.
##
## The clock only moves in tick(), called from the studio's simulation step, so scrubbing can
## fast-forward silently and then resume clips at the right offset.

const BUS := "DialogueBus"
const FX_PITCH := 0
const FX_BAND := 1
const FX_SPECTRUM := 2
const LIPSYNC_FPS := 12.0
const BABBLE_RATE := 16000.0
const SEC_PER_CHAR := 0.065

## filter presets: band-pass centre (Hz) and resonance; "none" bypasses the band-pass
const FILTERS := {
	"none": {},
	"radio": {"hz": 1700.0, "res": 0.65},
	"tiny_squeak": {"hz": 2600.0, "res": 0.45},
	"deep_bot": {"hz": 520.0, "res": 0.7},
}

var bus_idx := -1
var silent := false     # true while the studio fast-forwards (scrub / jump to shot)
var clock := 0.0
var last_speaker: Node3D = null
var manifest := {}
var _lines := {}        # node -> {player, start, until, path, voice, procedural}
var _levels := {}       # node -> mouth level 0..1, held between 12fps samples
var _sample_t := 0.0
var _live_node: Node3D = null
var _live_player: AudioStreamPlayer
var _live_playback: AudioStreamGeneratorPlayback
var _babble := Babble.new()
var _paused := false

func _ready() -> void:
	_setup_bus()
	_live_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = BABBLE_RATE
	gen.buffer_length = 0.25
	_live_player.stream = gen
	_live_player.bus = BUS
	add_child(_live_player)
	if FileAccess.file_exists("res://data/audio_manifest.json"):
		var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_manifest.json"))
		if m is Dictionary:
			manifest = m.get("files", {})

func _setup_bus() -> void:
	bus_idx = AudioServer.get_bus_index(BUS)
	if bus_idx != -1:
		return
	AudioServer.add_bus()
	bus_idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_idx, BUS)
	AudioServer.set_bus_send(bus_idx, "Master")
	AudioServer.add_bus_effect(bus_idx, AudioEffectPitchShift.new(), FX_PITCH)
	AudioServer.add_bus_effect(bus_idx, AudioEffectBandPassFilter.new(), FX_BAND)
	var spec := AudioEffectSpectrumAnalyzer.new()
	spec.buffer_length = 0.1
	spec.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(bus_idx, spec, FX_SPECTRUM)

## Applies a character's voice preset to the dialogue bus.
func apply_preset(voice: Dictionary) -> void:
	var pitch := AudioServer.get_bus_effect(bus_idx, FX_PITCH) as AudioEffectPitchShift
	pitch.pitch_scale = clampf(float(voice.get("pitch", 1.0)), 0.5, 2.0)
	var f: Dictionary = FILTERS.get(String(voice.get("filter", "none")), {})
	AudioServer.set_bus_effect_enabled(bus_idx, FX_BAND, not f.is_empty())
	if not f.is_empty():
		var band := AudioServer.get_bus_effect(bus_idx, FX_BAND) as AudioEffectBandPassFilter
		band.cutoff_hz = f["hz"]
		band.resonance = f["res"]

static func resolve(path: String) -> String:
	if path == "":
		return ""
	var full := path if path.begins_with("res://") else "res://assets/audio/" + path
	return full if ResourceLoader.exists(full) else ""

## Seconds a line lasts: explicit duration, else the clip (manifest or stream), else its text.
func line_length(path: String, text: String, duration := -1.0) -> float:
	if duration > 0.0:
		return duration
	if manifest.has(path):
		return float(manifest[path])
	var full := resolve(path)
	if full != "":
		var s := load(full) as AudioStream
		if s:
			return s.get_length()
	return maxf(0.5, text.length() * SEC_PER_CHAR)

## Speaks a line; returns its duration. `offset` starts a clip part-way (resuming after a scrub).
func say(node: Node3D, voice: Dictionary, path: String, text: String, duration := -1.0, offset := 0.0) -> float:
	stop(node)
	var length := line_length(path, text, duration)
	var line := {"player": null, "start": clock - offset, "until": clock - offset + length, "path": path,
		"voice": voice, "procedural": resolve(path) == ""}
	_lines[node] = line
	last_speaker = node
	if not silent and not line["procedural"]:
		_play(node, line, offset)
	return length

func _play(node: Node3D, line: Dictionary, offset: float) -> void:
	apply_preset(line["voice"])
	var p := AudioStreamPlayer.new()
	p.stream = load(resolve(String(line["path"])))
	p.bus = BUS
	add_child(p)
	p.play(maxf(0.0, offset))
	p.stream_paused = _paused
	line["player"] = p

## After a silent fast-forward: start every clip that should be sounding, at its offset.
func resume_audio() -> void:
	for n in _lines:
		var line: Dictionary = _lines[n]
		if not line["procedural"] and line["player"] == null:
			_play(n, line, clock - float(line["start"]))

func set_paused(on: bool) -> void:
	_paused = on
	for n in _lines:
		var p = _lines[n]["player"]
		if p and is_instance_valid(p):
			(p as AudioStreamPlayer).stream_paused = on

func stop(node: Node3D) -> void:
	if _lines.has(node):
		var p = _lines[node]["player"]
		if p and is_instance_valid(p):
			(p as AudioStreamPlayer).queue_free()
		_lines.erase(node)
	_levels.erase(node)

func stop_all() -> void:
	for n in _lines.keys():
		stop(n)
	live(null, {})
	last_speaker = null

## Live test input: while Talk is held, `node` speaks with a synthesized babble through its preset.
func live(node: Node3D, voice: Dictionary) -> void:
	if node == _live_node:
		return
	_live_node = node
	if node == null:
		_live_player.stop()
		_live_playback = null
		return
	last_speaker = node
	apply_preset(voice)
	_babble.reset(randi())
	_live_player.play()
	_live_playback = _live_player.get_stream_playback() as AudioStreamGeneratorPlayback

func is_talking(node: Node3D) -> bool:
	return _lines.has(node) or node == _live_node

## Mouth level: 0..1 from the spectrum, or -1 when the procedural bounce should be used.
func level(node: Node3D) -> float:
	if node == _live_node:
		return _levels.get(node, 0.0)
	if _lines.has(node) and not _lines[node]["procedural"] and _lines[node]["player"] != null:
		return _levels.get(node, 0.0)
	return -1.0

## The character currently speaking (most recent line), or null.
func speaker() -> Node3D:
	if last_speaker and is_talking(last_speaker):
		return last_speaker
	for n in _lines:
		return n
	return null

## Babble frames stream in real time.
func _process(_dt: float) -> void:
	if _live_playback:
		for i in _live_playback.get_frames_available():
			var s := _babble.next(BABBLE_RATE)
			_live_playback.push_frame(Vector2(s, s))

## Studio clock step: ends lines, samples the spectrum 12 times a second.
func tick(dt: float) -> void:
	clock += dt
	for n in _lines.keys():
		if not is_instance_valid(n) or clock >= float(_lines[n]["until"]):
			stop(n)
	_sample_t += dt
	if _sample_t < 1.0 / LIPSYNC_FPS:
		return
	_sample_t = 0.0
	var energy := 0.0
	var spec := AudioServer.get_bus_effect_instance(bus_idx, FX_SPECTRUM) as AudioEffectSpectrumAnalyzerInstance
	if spec and not silent:
		var m := spec.get_magnitude_for_frequency_range(200.0, 3000.0)
		energy = clampf((linear_to_db((m.x + m.y) * 0.5) + 62.0) / 40.0, 0.0, 1.0)
	for n in _lines:
		_levels[n] = energy
	if _live_node:
		_levels[_live_node] = energy

## Formant babble: a buzzy source through two vowel resonators, chopped into syllables.
class Babble:
	const VOWELS := [[730.0, 1090.0], [530.0, 1840.0], [270.0, 2290.0], [570.0, 840.0], [300.0, 870.0]]
	var rng := RandomNumberGenerator.new()
	var phase := 0.0
	var t := 0.0
	var syl_end := 0.0
	var syl_len := 0.15
	var gap := 0.05
	var f1 := 700.0
	var f2 := 1200.0
	var y1 := [0.0, 0.0]
	var y2 := [0.0, 0.0]

	func reset(seed: int) -> void:
		rng.seed = seed
		t = 0.0
		syl_end = 0.0

	func next(rate: float) -> float:
		t += 1.0 / rate
		if t >= syl_end:
			var v: Array = VOWELS[rng.randi() % VOWELS.size()]
			f1 = v[0]
			f2 = v[1]
			syl_len = rng.randf_range(0.09, 0.19)
			gap = rng.randf_range(0.02, 0.09)
			syl_end = t + syl_len + gap
		var into := syl_len - (syl_end - gap - t)
		var env := 0.0
		if into >= 0.0 and into < syl_len:
			env = sin(PI * into / syl_len)
		var f0 := 150.0 * (1.0 + 0.08 * sin(t * 9.0))
		phase = fmod(phase + f0 / rate, 1.0)
		var src := (phase * 2.0 - 1.0) * env
		var out := _res(src, f1, 90.0, rate, 0) + 0.6 * _res(src, f2, 120.0, rate, 1)
		return clampf(out * 0.18, -1.0, 1.0)

	func _res(x: float, f: float, bw: float, rate: float, i: int) -> float:
		var r := exp(-PI * bw / rate)
		var a1 := 2.0 * r * cos(TAU * f / rate)
		var a2 := -r * r
		var y: float = (1.0 - r) * x + a1 * y1[i] + a2 * y2[i]
		y2[i] = y1[i]
		y1[i] = y
		return y
