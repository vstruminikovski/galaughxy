class_name JoyPad
extends Control

## Draws the floating joystick while a thumb is on the left side.
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var active := false

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	draw_circle(origin, 70.0, Color(1, 1, 1, 0.12))
	draw_arc(origin, 70.0, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
	draw_circle(knob, 26.0, Color(0.22, 0.9, 1.0, 0.7))
