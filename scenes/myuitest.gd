extends PanelContainer
class_name MyUITest

const UIStyleScript = preload("res://scripts/ui/UIStyle.gd")

@export var blur_strength: float = 1.7
@export var tint: Color = UIStyleScript.CARD_TINT
@export_range(0.0, 1.0, 0.01) var tint_strength: float = 0.08
@export_range(0.0, 1.0, 0.01) var glass_alpha: float = 0.34
@export_range(0.5, 1.5, 0.01) var brightness: float = 1.02
@export_range(0.0, 0.5, 0.01) var gradient_strength: float = 0.08
@export_range(0.0, 0.5, 0.01) var edge_highlight_strength: float = 0.12
@export var hover_glow_enabled := true

var _blur_rect
var _material: ShaderMaterial
var _content_margin
var _hover_lift: float = 0.0:
	set(value):
		_hover_lift = value
		_update_blur()


func _ready() -> void:
	_blur_rect = get_node_or_null("BlurRect")
	_content_margin = get_node_or_null("ContentMargin")
	if _blur_rect != null:
		var shared_material: ShaderMaterial = _blur_rect.material as ShaderMaterial
		if shared_material != null:
			_material = shared_material.duplicate() as ShaderMaterial
			_blur_rect.material = _material
	resized.connect(_update_blur)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh()


func refresh() -> void:
	_update_content_margin()
	_update_blur()


func _update_content_margin() -> void:
	if _content_margin == null:
		return



func _update_blur() -> void:
	if _material == null:
		return

	_material.set_shader_parameter("u_panel_size", Vector2(max(size.x, 1.0), max(size.y, 1.0)))
	_material.set_shader_parameter("u_corner_radius", float(UIStyleScript.CARD_RADIUS))
	_material.set_shader_parameter("u_distortion_intensity", 0.35)
	_material.set_shader_parameter("u_blur_intensity", clamp(blur_strength * 0.42, 0.65, 1.35))
	_material.set_shader_parameter("u_alpha", clamp(glass_alpha + (_hover_lift * 0.04), 0.0, 1.0))
	_material.set_shader_parameter("u_tint", Color(tint.r, tint.g, tint.b, 1.0))
	_material.set_shader_parameter("u_tint_strength", tint_strength)
	_material.set_shader_parameter("u_brightness", brightness + (_hover_lift * 0.06))
	_material.set_shader_parameter("u_gradient_strength", gradient_strength)
	_material.set_shader_parameter("u_edge_highlight_strength", edge_highlight_strength + (_hover_lift * 0.05))
	if _blur_rect != null:
		_blur_rect.self_modulate = Color(1.0, 1.0, 1.0, 1.0 + (_hover_lift * 0.08))


func _on_mouse_entered() -> void:
	if hover_glow_enabled:
		_animate_hover(1.0)


func _on_mouse_exited() -> void:
	if hover_glow_enabled:
		_animate_hover(0.0)


func _animate_hover(target: float) -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_hover_lift", target, UIStyleScript.ANIM_MEDIUM)
