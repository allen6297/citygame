extends Button
class_name ToolbarButton

const UIStyleScript = preload("res://scripts/ui/UIStyle.gd")

@export var accent: Color = UIStyleScript.ACCENT


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(114.0, 46.0)
	pivot_offset = custom_minimum_size * 0.5
	sync_pressed_state()


func sync_pressed_state() -> void:
	if toggle_mode and button_pressed:
		_apply_style(UIStyleScript.BUTTON_PRESSED, Color(accent.r, accent.g, accent.b, 0.38))
	else:
		_apply_style(UIStyleScript.BUTTON_IDLE, UIStyleScript.BUTTON_BORDER)


func _on_mouse_entered() -> void:
	if toggle_mode and button_pressed:
		_apply_style(UIStyleScript.BUTTON_PRESSED, Color(accent.r, accent.g, accent.b, 0.38))
		_animate_to(Vector2(0.0, -1.0), Vector2.ONE * 1.01)
		return
	_apply_style(UIStyleScript.BUTTON_HOVER, UIStyleScript.BUTTON_HOVER_BORDER)
	_animate_to(Vector2(0.0, -2.0), Vector2.ONE * 1.03)


func _on_mouse_exited() -> void:
	if toggle_mode and button_pressed:
		_apply_style(UIStyleScript.BUTTON_PRESSED, Color(accent.r, accent.g, accent.b, 0.38))
		_animate_to(Vector2.ZERO, Vector2.ONE)
		return
	_apply_style(UIStyleScript.BUTTON_IDLE, UIStyleScript.BUTTON_BORDER)
	_animate_to(Vector2.ZERO, Vector2.ONE)


func _on_button_down() -> void:
	_apply_style(UIStyleScript.BUTTON_PRESSED, Color(accent.r, accent.g, accent.b, 0.38))
	_animate_to(Vector2(0.0, 1.0), Vector2.ONE * 0.97)


func _on_button_up() -> void:
	if toggle_mode and button_pressed:
		_apply_style(UIStyleScript.BUTTON_PRESSED, Color(accent.r, accent.g, accent.b, 0.38))
		_animate_to(Vector2.ZERO, Vector2.ONE)
	elif get_global_rect().has_point(get_viewport().get_mouse_position()):
		_on_mouse_entered()
	else:
		_on_mouse_exited()


func _animate_to(offset: Vector2, target_scale: Vector2) -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target_scale, UIStyleScript.ANIM_FAST)
	tween.tween_property(self, "self_modulate:a", 1.0 - (0.04 if offset.y > 0.0 else 0.0), UIStyleScript.ANIM_FAST)


func _apply_style(fill_color: Color, border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = UIStyleScript.CARD_RADIUS
	style.corner_radius_top_right = UIStyleScript.CARD_RADIUS
	style.corner_radius_bottom_right = UIStyleScript.CARD_RADIUS
	style.corner_radius_bottom_left = UIStyleScript.CARD_RADIUS
	style.shadow_color = UIStyleScript.BUTTON_SHADOW
	style.shadow_size = 8
	style.content_margin_left = 18
	style.content_margin_top = 11
	style.content_margin_right = 18
	style.content_margin_bottom = 11
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)
	add_theme_stylebox_override("disabled", style)
	var font_color := UIStyleScript.TEXT_SECONDARY
	if fill_color == UIStyleScript.BUTTON_HOVER or fill_color == UIStyleScript.BUTTON_PRESSED:
		font_color = UIStyleScript.BUTTON_TEXT_HOVER
	add_theme_color_override("font_color", font_color)
	add_theme_font_size_override("font_size", 15)
