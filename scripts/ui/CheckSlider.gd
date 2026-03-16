extends Button
class_name CheckSlider

const UIStyleScript = preload("res://scripts/ui/UIStyle.gd")

@export var label_text: String = "Enabled"

@onready var _switch_layer: Control = get_node_or_null("Content/SwitchLayer") as Control
@onready var _track: MyUITest = get_node_or_null("Content/SwitchLayer/Track") as MyUITest
@onready var _knob: MyUITest = get_node_or_null("Content/SwitchLayer/Knob") as MyUITest

var _hovered: bool = false


func _ready() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(100.0, 50.0)
	theme_type_variation = &"CheckSlider"
	toggled.connect(_on_toggled)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	pivot_offset = custom_minimum_size * 0.5
	_apply_switch_state(button_pressed, false)


func _on_toggled(toggled_on: bool) -> void:
	_apply_switch_state(toggled_on, true)


func _on_mouse_entered() -> void:
	_hovered = true
	_animate_scale(Vector2.ONE * 1.02)
	_apply_switch_state(button_pressed, true)


func _on_mouse_exited() -> void:
	_hovered = false
	_animate_scale(Vector2.ONE)
	_apply_switch_state(button_pressed, true)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	_apply_switch_state(button_pressed, false)


func _apply_switch_state(toggled_on: bool, animated: bool) -> void:
	if _switch_layer == null or _track == null or _knob == null:
		return

	self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	_track.hover_glow_enabled = false
	_knob.hover_glow_enabled = false
	_track.content_padding = Vector2.ZERO
	_knob.content_padding = Vector2.ZERO
	_track.tint = Color(0.93, 0.97, 1.0, 1.0)
	_track.tint_strength = 0.1
	_track.glass_alpha = 0.24
	_track.blur_strength = 1.2
	_track.brightness = 1.02
	_track.gradient_strength = 0.08
	_track.edge_highlight_strength = 0.2
	if toggled_on:
		_track.tint = Color(0.28, 0.82, 0.42, 1.0)
		_track.tint_strength = 0.56
		_track.glass_alpha = 0.66
		_track.blur_strength = 1.28
		_track.brightness = 1.08
		_track.edge_highlight_strength = 0.24
	if _hovered and not toggled_on:
		_track.glass_alpha = 0.29
		_track.brightness = 1.05
		_track.edge_highlight_strength = 0.23
	_track.refresh()

	_knob.tint = Color(0.985, 0.992, 1.0, 1.0)
	_knob.tint_strength = 0.03
	_knob.glass_alpha = 0.82
	_knob.blur_strength = 0.82
	_knob.brightness = 1.1
	_knob.gradient_strength = 0.06
	_knob.edge_highlight_strength = 0.28
	if toggled_on:
		_knob.brightness = 1.12
		_knob.edge_highlight_strength = 0.3
	_knob.refresh()

	var knob_size: Vector2 = _knob.size
	if knob_size == Vector2.ZERO:
		knob_size = _knob.custom_minimum_size
	var track_size: Vector2 = _switch_layer.size
	if track_size == Vector2.ZERO:
		track_size = _switch_layer.custom_minimum_size

	var inset: float = max((track_size.y - knob_size.y) * 0.5, 0.0)
	var target_x: float = inset
	if toggled_on:
		target_x = max(track_size.x - knob_size.x - inset, inset)
	var target_y: float = (track_size.y - knob_size.y) * 0.5
	var target_scale: Vector2 = Vector2.ONE
	if toggled_on:
		target_scale = Vector2(1.015, 1.015)
	elif _hovered:
		target_scale = Vector2(1.008, 1.008)

	if animated:
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_QUART)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(_knob, "position:x", target_x, UIStyleScript.ANIM_FAST)
		tween.parallel().tween_property(_knob, "position:y", target_y, UIStyleScript.ANIM_FAST)
		tween.parallel().tween_property(_knob, "scale", target_scale, UIStyleScript.ANIM_FAST)
	else:
		_knob.position.x = target_x
		_knob.position.y = target_y
		_knob.scale = target_scale


func _animate_scale(target_scale: Vector2) -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target_scale, UIStyleScript.ANIM_FAST)
