class_name Toolbox
extends PanelContainer

## A floating studio toolbox: title bar (drag to move), minimize and close.
## The panel stops mouse / touch so clicks never fall through to the camera or joystick;
## its buttons never take keyboard focus, so Space / Tab / hotkeys keep working.

signal closed

var body: VBoxContainer
var title_label: Label
var _drag := false
var _min_btn: Button
var _width := 300.0

func _init(title: String, width: float, at: Vector2) -> void:
	_width = width
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = at
	custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.gui_input.connect(_on_head_input)
	v.add_child(head)
	title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title_label)
	_min_btn = button("—", Vector2(36, 32))
	_min_btn.tooltip_text = "Minimize"
	_min_btn.pressed.connect(toggle_minimized)
	head.add_child(_min_btn)
	var x := button("✕", Vector2(36, 32))
	x.tooltip_text = "Close"
	x.pressed.connect(func(): visible = false; closed.emit())
	head.add_child(x)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(body)

static func button(text: String, min_size := Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b

func toggle_minimized() -> void:
	body.visible = not body.visible
	_min_btn.text = "▢" if not body.visible else "—"
	reset_size()

## Tabs: a row of toggle buttons; the page with the pressed button is shown.
func tabs(names: Array) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var group := ButtonGroup.new()
	var pages := {}
	var buttons := {}
	for n in names:
		var b := button(String(n), Vector2(0, 38))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		page.visible = false
		body.add_child(page)
		pages[n] = page
		buttons[n] = b
		b.pressed.connect(func():
			for k in pages:
				(pages[k] as Control).visible = k == n
			reset_size())
	if not names.is_empty():
		buttons[names[0]].button_pressed = true
		pages[names[0]].visible = true
	return {"buttons": buttons, "pages": pages}

func select_tab(t: Dictionary, name: String) -> void:
	if t["buttons"].has(name):
		(t["buttons"][name] as Button).button_pressed = true
		for k in t["pages"]:
			(t["pages"][k] as Control).visible = k == name
		reset_size()

func _on_head_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		accept_event()
	elif event is InputEventScreenTouch:
		_drag = event.pressed
		accept_event()
	elif _drag and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		var vp := get_viewport_rect().size
		position = (position + event.relative).clamp(Vector2(-size.x + 80, 0), vp - Vector2(80, 40))
		accept_event()
