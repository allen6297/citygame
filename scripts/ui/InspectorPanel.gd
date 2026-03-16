extends Control
class_name InspectorPanel

const UIStyleScript = preload("res://scripts/ui/UIStyle.gd")
const SCREEN_MARGIN := 24.0

@export var panel_width := 360.0
@export var top_margin := 92.0
@export var bottom_margin := 24.0

@onready var _panel = get_node_or_null("InspectorGlass")

var _is_open := false


func _ready() -> void:
	visible = true
	top_level = true
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_sync_layout)
	_sync_layout()
	apply_state(false)


func toggle() -> void:
	set_open(not _is_open)


func configure_bounds(new_top_margin: float, new_bottom_margin: float) -> void:
	top_margin = new_top_margin
	bottom_margin = new_bottom_margin
	_sync_layout()


func set_open(value: bool) -> void:
	if _is_open == value:
		return
	_is_open = value
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", _get_target_position(), UIStyleScript.ANIM_MEDIUM)
	tween.parallel().tween_property(self, "modulate:a", 1.0 if value else 0.0, UIStyleScript.ANIM_MEDIUM)


func apply_state(value: bool) -> void:
	_is_open = value
	position = _get_target_position()
	modulate.a = 1.0 if value else 0.0


func is_open() -> bool:
	return _is_open


func _sync_layout() -> void:
	# The inspector keeps its own width and recomputes its resting position
	# whenever the viewport changes, so it stays docked on desktop resizes.
	size = Vector2(panel_width, maxf(get_viewport_rect().size.y - top_margin - bottom_margin, 0.0))
	position = _get_target_position()


func _get_target_position() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var open_x: float = viewport_size.x - panel_width - SCREEN_MARGIN
	var closed_x: float = viewport_size.x + 28.0
	return Vector2(open_x if _is_open else closed_x, top_margin)
