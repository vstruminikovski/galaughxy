class_name Controls
extends RefCounted

## Every studio control is a Godot InputMap action. Keyboard keys are bound here; touch HUD buttons
## call Input.action_press / action_release on the same actions, and the Director drives
## characters through Main.act() with the same action names, so humans and the AI trigger
## identical movement, sounds and On Twos animation.
##
## Keys: WASD/arrows move · Space talk (rises in fly mode) · J hop · 1-6 expressions
## F wave · G point · V facepalm · B shrug · Q/7 drip · E/8 surge · 9 flood · 0 drain
## Z/X/C static/slider/drone · N fly · M maps · I cast · P director · T timeline
## K play/pause · R overdub · Tab next character · O 12fps On Twos · Y PNG frame · Esc close

const BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"talk": [KEY_SPACE],
	"hop": [KEY_J],
	"expr_1": [KEY_1], "expr_2": [KEY_2], "expr_3": [KEY_3],
	"expr_4": [KEY_4], "expr_5": [KEY_5], "expr_6": [KEY_6],
	"emote_wave": [KEY_F],
	"emote_point": [KEY_G],
	"emote_facepalm": [KEY_V],
	"emote_shrug": [KEY_B],
	"chaos_1": [KEY_Q, KEY_7], "chaos_2": [KEY_E, KEY_8], "chaos_3": [KEY_9], "chaos_drain": [KEY_0],
	"chaos_next": [],
	"cam_static": [KEY_Z], "cam_slider": [KEY_X], "cam_drone": [KEY_C],
	"fly": [KEY_N],
	"maps": [KEY_M],
	"cast": [KEY_I],
	"director": [KEY_P],
	"timeline": [KEY_T],
	"play_pause": [KEY_K],
	"overdub": [KEY_R],
	"next_actor": [KEY_TAB],
	"twos": [KEY_O],
	"png": [KEY_Y],
	"cancel": [KEY_ESCAPE],
}

## One-shot actions: handled on press.
const TRIGGERS := ["hop", "expr_1", "expr_2", "expr_3", "expr_4", "expr_5", "expr_6",
	"emote_wave", "emote_point", "emote_facepalm", "emote_shrug",
	"chaos_1", "chaos_2", "chaos_3", "chaos_drain", "chaos_next",
	"cam_static", "cam_slider", "cam_drone", "fly", "maps", "cast", "director",
	"timeline", "play_pause", "overdub", "next_actor", "twos", "png", "cancel"]

## Allowed while free-flying (Minecraft-style: move, look, rise, plus the drawers).
const FLY_OK := ["move_left", "move_right", "move_forward", "move_back", "talk", "fly", "maps", "cast", "director", "png", "cancel"]

## Allowed while a drawer is open.
const DRAWER_OK := ["maps", "cast", "director", "timeline", "cancel"]

const EMOTES := ["emote_wave", "emote_point", "emote_facepalm", "emote_shrug"]

static func setup() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.keycode = key
			InputMap.action_add_event(action, ev)

## A tap from a touch button: press now, release on the next frame.
static func tap(tree: SceneTree, action: String) -> void:
	Input.action_press(action)
	await tree.process_frame
	await tree.process_frame
	Input.action_release(action)
