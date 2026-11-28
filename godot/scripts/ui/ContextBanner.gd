class_name ContextBanner
extends Control

## Android-style floating hint pill, top-centre. Shows the live key bindings for whatever you are
## doing (aiming a camera path, recording a take, flying...). [✕] dismisses that tip for good;
## Settings can turn tips off or bring dismissed ones back. Hidden in Clean HUD.
## The wrapper ignores the mouse; only the card and its button catch clicks and taps.

const SETTINGS := "user://settings.cfg"

var enabled := true
var dismissed := {}
var current := ""
var _card: PanelContainer
var _icon: Label
var _text: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 72
	offset_bottom = 120
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.18, 0.96)
	sb.set_corner_radius_all(26)
	sb.content_margin_left = 18
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_card.add_child(row)
	_icon = Label.new()
	_icon.add_theme_font_size_override("font_size", 18)
	row.add_child(_icon)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 14)
	_text.custom_minimum_size = Vector2(0, 30)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_text)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.mouse_filter = Control.MOUSE_FILTER_STOP
	x.custom_minimum_size = Vector2(36, 32)
	x.tooltip_text = "Dismiss this tip"
	x.pressed.connect(dismiss)
	row.add_child(x)
	_load()
	_card.visible = false

## Shows a tip (id identifies it for dismissing). Empty text hides the banner.
func show_tip(id: String, icon: String, text: String) -> void:
	current = id
	var show := enabled and text != "" and not dismissed.has(id)
	_card.visible = show
	if show:
		_icon.text = icon
		_text.text = text

func is_showing() -> bool:
	return _card.visible

func card_rect() -> Rect2:
	return _card.get_global_rect() if _card.visible else Rect2()

func dismiss() -> void:
	if current != "":
		dismissed[current] = true
	_card.visible = false
	_save()

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_card.visible = false
	_save()

func reset_dismissed() -> void:
	dismissed.clear()
	_save()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		enabled = bool(cfg.get_value("tips", "enabled", true))
		for id in cfg.get_value("tips", "dismissed", []):
			dismissed[String(id)] = true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("tips", "enabled", enabled)
	cfg.set_value("tips", "dismissed", dismissed.keys())
	cfg.save(SETTINGS)
