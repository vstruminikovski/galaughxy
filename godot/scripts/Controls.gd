class_name Controls
extends RefCounted

## Every studio control is a Godot InputMap action. Keyboard keys are bound here; touch buttons call
## Input.action_press / action_release on the same actions; the Director drives characters through
## Main.act() with the same action names. The Controls panel and context tips read the bindings back
## from InputMap at runtime, so they always show the real keys.

const BINDINGS := {
	# movement
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"talk": [KEY_SPACE], "hop": [KEY_J], "next_actor": [KEY_TAB],
	"fly": [KEY_N], "fly_up": [KEY_SPACE], "fly_down": [],
	# character
	"expr_1": [KEY_1], "expr_2": [KEY_2], "expr_3": [KEY_3], "expr_4": [KEY_4], "expr_5": [KEY_5], "expr_6": [KEY_6],
	"emote_wave": [KEY_F], "emote_point": [KEY_G], "emote_facepalm": [KEY_V], "emote_shrug": [KEY_B],
	"ability_1": [KEY_Y], "ability_2": [KEY_U], "ability_3": [KEY_O], "ability_4": [KEY_H], "ability_5": [KEY_L],
	# map chaos
	"chaos_1": [KEY_Q, KEY_7], "chaos_2": [KEY_E, KEY_8], "chaos_3": [KEY_9], "chaos_drain": [KEY_0], "chaos_next": [],
	# cameras
	"cam_static": [KEY_Z], "cam_slider": [KEY_X], "cam_drone": [KEY_C],
	"path_pin": [KEY_ENTER, KEY_KP_ENTER], "path_undo": [KEY_BACKSPACE], "path_finish": [KEY_PERIOD],
	"path_preview": [KEY_COMMA], "path_shorter": [KEY_BRACKETLEFT], "path_longer": [KEY_BRACKETRIGHT],
	# timeline and takes
	"timeline": [KEY_T, KEY_F3], "play_pause": [KEY_K], "overdub": [KEY_R],
	"take_toggle": [KEY_BACKSLASH], "take_merge": [KEY_EQUAL], "take_discard": [KEY_MINUS], "cam_key": [KEY_APOSTROPHE],
	# windows
	"tb_camera": [KEY_F1], "tb_character": [KEY_F2], "maps": [KEY_M, KEY_F4], "cast": [KEY_I], "director": [KEY_P],
	"controls": [KEY_SLASH, KEY_F5], "hide_all": [KEY_QUOTELEFT], "cancel": [KEY_ESCAPE],
}

## One-shot actions: handled on press.
const TRIGGERS := ["hop", "next_actor", "fly",
	"expr_1", "expr_2", "expr_3", "expr_4", "expr_5", "expr_6",
	"emote_wave", "emote_point", "emote_facepalm", "emote_shrug",
	"ability_1", "ability_2", "ability_3", "ability_4", "ability_5",
	"chaos_1", "chaos_2", "chaos_3", "chaos_drain", "chaos_next",
	"cam_static", "cam_slider", "cam_drone",
	"path_pin", "path_undo", "path_finish", "path_preview", "path_shorter", "path_longer",
	"timeline", "play_pause", "overdub", "take_toggle", "take_merge", "take_discard", "cam_key",
	"tb_camera", "tb_character", "maps", "cast", "director", "controls", "hide_all", "cancel"]

## Allowed while free-flying (Minecraft-style: move, look, rise, plus windows and the camera path).
const FLY_OK := ["move_left", "move_right", "move_forward", "move_back", "talk", "fly", "fly_up", "fly_down",
	"path_pin", "path_undo", "path_finish", "path_preview", "path_shorter", "path_longer",
	"tb_camera", "tb_character", "timeline", "maps", "cast", "director", "controls", "hide_all", "cancel"]

const EMOTES := ["emote_wave", "emote_point", "emote_facepalm", "emote_shrug"]

## action -> [category, description, touch]
const INFO := {
	"move_left": ["Movement", "Walk left", "Left thumb stick"], "move_right": ["Movement", "Walk right", "Left thumb stick"],
	"move_forward": ["Movement", "Walk forward (fly: along your view)", "Left thumb stick"],
	"move_back": ["Movement", "Walk back", "Left thumb stick"],
	"talk": ["Movement", "Talk (hold) · live voice through the character's preset", "Character ▸ TALK (hold)"],
	"hop": ["Movement", "Hop", "Character ▸ Move ▸ HOP"],
	"next_actor": ["Movement", "Control the next character", "Character ▸ Next · or tap a character"],
	"fly": ["Camera", "Free fly on / off (studio only, never during playback)", "Menu ▸ Fly"],
	"fly_up": ["Camera", "Fly: rise", "Path bar ▸ ▲ (hold)"], "fly_down": ["Camera", "Fly: sink", "Path bar ▸ ▼ (hold)"],
	"expr_1": ["Character", "Expression: Deadpan", "Character ▸ Emotions"], "expr_2": ["Character", "Expression: Smirk", "Character ▸ Emotions"],
	"expr_3": ["Character", "Expression: Panic", "Character ▸ Emotions"], "expr_4": ["Character", "Expression: Angry", "Character ▸ Emotions"],
	"expr_5": ["Character", "Expression: Happy", "Character ▸ Emotions"], "expr_6": ["Character", "Expression: Shocked", "Character ▸ Emotions"],
	"emote_wave": ["Character", "Emote: Wave", "Character ▸ Emotes"], "emote_point": ["Character", "Emote: Point", "Character ▸ Emotes"],
	"emote_facepalm": ["Character", "Emote: Facepalm", "Character ▸ Emotes"], "emote_shrug": ["Character", "Emote: Shrug", "Character ▸ Emotes"],
	"ability_1": ["Abilities", "Ability 1 of the controlled character", "Character ▸ Abilities"],
	"ability_2": ["Abilities", "Ability 2", "Character ▸ Abilities"], "ability_3": ["Abilities", "Ability 3", "Character ▸ Abilities"],
	"ability_4": ["Abilities", "Ability 4", "Character ▸ Abilities"], "ability_5": ["Abilities", "Ability 5", "Character ▸ Abilities"],
	"chaos_1": ["Map chaos", "Map gag, stage 1", "Character ▸ Abilities ▸ Map gags"], "chaos_2": ["Map chaos", "Map gag, stage 2", "Character ▸ Abilities ▸ Map gags"],
	"chaos_3": ["Map chaos", "Map gag, stage 3", "Character ▸ Abilities ▸ Map gags"], "chaos_drain": ["Map chaos", "Reset the map", "Character ▸ Abilities ▸ Map gags"],
	"cam_static": ["Camera", "Map camera: Static (during playback: cut + record)", "Camera ▸ 2. Static"],
	"cam_slider": ["Camera", "Map camera: Slider", "Camera ▸ 3. Sliders"], "cam_drone": ["Camera", "Map camera: Drone", "Camera ▸ 1. Drone"],
	"path_pin": ["Camera path", "Drop a pin at the current view", "Path bar ▸ Drop Pin"],
	"path_undo": ["Camera path", "Undo the last pin", "Path bar ▸ Undo Pin"],
	"path_finish": ["Camera path", "Finish the path and save it into the shot", "Path bar ▸ Finish Path"],
	"path_preview": ["Camera path", "Preview the path", "Path bar ▸ Preview"],
	"path_shorter": ["Camera path", "Path duration −0.5 s", "Path bar ▸ Duration slider"],
	"path_longer": ["Camera path", "Path duration +0.5 s", "Path bar ▸ Duration slider"],
	"timeline": ["Timeline", "Show / hide the Timeline toolbox", "Menu ▸ Timeline"],
	"play_pause": ["Timeline", "Play / pause the shot", "Timeline ▸ ▶"],
	"overdub": ["Timeline", "Overdub: record over the playing shot (merges on stop)", "Timeline ▸ ● OVERDUB"],
	"take_toggle": ["Timeline", "Start / stop a live take from the current time", "Timeline ▸ ● Take / ■ Stop"],
	"take_merge": ["Timeline", "Merge the stopped take into the shot", "Timeline ▸ Merge"],
	"take_discard": ["Timeline", "Discard the stopped take", "Timeline ▸ Discard"],
	"cam_key": ["Timeline", "Record a camera keyframe (current view) into the take", "Timeline ▸ 📸 Cam Key"],
	"tb_camera": ["Windows", "Camera toolbox", "Menu ▸ Camera"], "tb_character": ["Windows", "Character toolbox", "Menu ▸ Character"],
	"maps": ["Windows", "World toolbox: maps and expansions", "Menu ▸ World"], "cast": ["Windows", "Cast toolbox", "Menu ▸ Cast"],
	"director": ["Windows", "Director toolbox", "Menu ▸ Director"], "controls": ["Windows", "Controls reference", "Menu ▸ ?"],
	"hide_all": ["Windows", "Hide / show all toolboxes", "Menu ▸ Hide All"],
	"cancel": ["Windows", "Close windows · stop clean playback · cancel aiming", "Tap the screen during clean playback"],
}

const CATEGORY_ORDER := ["Movement", "Character", "Abilities", "Map chaos", "Camera", "Camera path", "Timeline", "Windows"]

## Friendlier keycap text for punctuation keys (matched case-insensitively).
const KEYCAPS := {"quoteleft": "`", "bracketleft": "[", "bracketright": "]", "backslash": "\\", "apostrophe": "'",
	"period": ".", "comma": ",", "slash": "/", "equal": "=", "minus": "-", "kp enter": "Num Enter", "backspace": "⌫"}

static func setup() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.keycode = key
			InputMap.action_add_event(action, ev)

## The keys bound to an action right now, as short keycap labels ("Space", "Y", "Enter").
static func keys(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := (ev as InputEventKey).keycode
			if k == 0:
				k = (ev as InputEventKey).physical_keycode
			var name := OS.get_keycode_string(k)
			out.append(KEYCAPS.get(name.to_lower(), name))
	return out

## "Y" or "Q / 7" for use in hints.
static func key_label(action: String) -> String:
	var k := keys(action)
	return " / ".join(k) if not k.is_empty() else "—"

## A tap from a touch button: press now, release two frames later.
static func tap(tree: SceneTree, action: String) -> void:
	Input.action_press(action)
	await tree.process_frame
	await tree.process_frame
	Input.action_release(action)
