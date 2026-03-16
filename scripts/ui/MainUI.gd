extends Control
class_name MainUI
signal build_tool_selected(tool_id: String)

const BUILD_TOOL_ROADS := "roads"
const BUILD_TOOL_ZONES := "zones"
const BUILD_TOOL_BULLDOZE := "bulldoze"

const UIStyleScript = preload("res://scripts/ui/UIStyle.gd")
const SIDE_PANEL_WIDTH := 360.0
const SIDE_PANEL_CLOSED_OFFSET := 28.0
const SIDE_PANEL_SCREEN_MARGIN := 24.0
const SIDE_PANEL_GAP := 20.0

@onready var toolbar_anchor: Control = get_node_or_null("%TopAnchor") as Control
@onready var bottom_anchor: Control = get_node_or_null("MarginContainer/BottomAnchor") as Control
@onready var inspector: InspectorPanel = get_node_or_null("%InspectorPanel") as InspectorPanel
@onready var controls_panel: Control = get_node_or_null("MarginContainer/Leftanchor/ControlsPanel") as Control
@onready var controls_glass: Control = get_node_or_null("MarginContainer/Leftanchor/ControlsPanel/ControlsGlass") as Control
@onready var settings_button: Button = get_node_or_null("MarginContainer/TopAnchor/ToolbarCard/MarginContainer/HBoxContainer/ToolbarButton3") as Button
@onready var status_label: Label = get_node_or_null("MarginContainer/BottomAnchor/SimulationCard/ContentMargin/Status") as Label
@onready var controls_label: Label = get_node_or_null("MarginContainer/BottomAnchor/BuildingCard/ContentMargin/HBoxContainer/VBoxContainer/Controls") as Label
@onready var roads_button: Button = get_node_or_null("MarginContainer/BottomAnchor/BuildingCard/ContentMargin/HBoxContainer/VBoxContainer2/ToolButtonRow/RoadsButton") as Button
@onready var zones_button: Button = get_node_or_null("MarginContainer/BottomAnchor/BuildingCard/ContentMargin/HBoxContainer/VBoxContainer2/ToolButtonRow/ZonesButton") as Button
@onready var bulldoze_button: Button = get_node_or_null("MarginContainer/BottomAnchor/BuildingCard/ContentMargin/HBoxContainer/VBoxContainer2/ToolButtonRow/BulldozeButton") as Button
@onready var controls_label_secondary: Label = get_node_or_null("MarginContainer/Leftanchor/ControlsPanel/ControlsGlass/ContentMargin/VBoxContainer/Controls") as Label

var bottom_cards: Array[Control] = []
var _controls_open := false
var _side_panel_sync_queued := false
var _active_build_tool := BUILD_TOOL_ROADS


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_queue_side_panel_sync)
	if controls_panel != null:
		controls_panel.top_level = true
	_collect_bottom_cards()
	_wire_interactions()
	_sync_side_panels()
	apply_controls_panel_state(false)
	_refresh_controls_text()
	_prepare_intro_state()
	_play_intro()
	_queue_side_panel_sync()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_controls_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			_toggle_inspector()
			get_viewport().set_input_as_handled()


func _collect_bottom_cards() -> void:
	bottom_cards.clear()
	for node_name: String in ["SimulationCard", "EconomyCard", "BuildingCard"]:
		var card: Control = get_node_or_null("MarginContainer/BottomAnchor/%s" % node_name) as Control
		if card != null:
			bottom_cards.append(card)


func _wire_interactions() -> void:
	var toggle_callable := Callable(self, "_toggle_inspector")
	if settings_button != null and inspector != null and not settings_button.pressed.is_connected(toggle_callable):
		settings_button.pressed.connect(toggle_callable)
	_connect_tool_button(roads_button, BUILD_TOOL_ROADS)
	_connect_tool_button(zones_button, BUILD_TOOL_ZONES)
	_connect_tool_button(bulldoze_button, BUILD_TOOL_BULLDOZE)
	_update_build_tool_buttons()


func _connect_tool_button(button: Button, tool_id: String) -> void:
	if button == null:
		return
	var select_callable := Callable(self, "_on_build_tool_pressed").bind(tool_id)
	if not button.pressed.is_connected(select_callable):
		button.pressed.connect(select_callable)


func _on_build_tool_pressed(tool_id: String) -> void:
	set_active_build_tool(tool_id)
	build_tool_selected.emit(tool_id)


func _toggle_inspector() -> void:
	if inspector != null:
		_sync_side_panels()
		inspector.toggle()


func _queue_side_panel_sync() -> void:
	if _side_panel_sync_queued:
		return
	_side_panel_sync_queued = true
	call_deferred("_flush_side_panel_sync")


func _flush_side_panel_sync() -> void:
	_side_panel_sync_queued = false
	_sync_side_panels()


func _toggle_controls_panel() -> void:
	set_controls_panel_open(not _controls_open)


func set_controls_panel_open(value: bool) -> void:
	if controls_panel == null or _controls_open == value:
		return
	_controls_open = value
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(controls_panel, "position", _get_controls_panel_target_position(), UIStyleScript.ANIM_MEDIUM)
	tween.parallel().tween_property(controls_panel, "modulate:a", 1.0 if value else 0.0, UIStyleScript.ANIM_MEDIUM)


func apply_controls_panel_state(value: bool) -> void:
	if controls_panel == null:
		return
	_controls_open = value
	controls_panel.visible = true
	controls_panel.position = _get_controls_panel_target_position()
	controls_panel.modulate.a = 1.0 if value else 0.0


func _sync_side_panels() -> void:
	var panel_bounds: Vector2 = _get_panel_vertical_bounds()
	if inspector != null:
		inspector.configure_bounds(panel_bounds.x, get_viewport_rect().size.y - panel_bounds.y)
	_sync_controls_panel(panel_bounds)


func _sync_controls_panel(panel_bounds: Vector2) -> void:
	if controls_panel == null:
		return
	controls_panel.size = Vector2(SIDE_PANEL_WIDTH, maxf(panel_bounds.y - panel_bounds.x, 0.0))
	controls_panel.position = _get_controls_panel_target_position()
	if controls_glass != null:
		controls_glass.anchor_left = 0.0
		controls_glass.anchor_top = 0.0
		controls_glass.anchor_right = 1.0
		controls_glass.anchor_bottom = 1.0
		controls_glass.offset_left = 0.0
		controls_glass.offset_top = 0.0
		controls_glass.offset_right = 0.0
		controls_glass.offset_bottom = 0.0


func _get_controls_panel_target_position() -> Vector2:
	var open_x: float = SIDE_PANEL_SCREEN_MARGIN
	var closed_x: float = -controls_panel.size.x - SIDE_PANEL_CLOSED_OFFSET
	var panel_bounds: Vector2 = _get_panel_vertical_bounds()
	var centered_y: float = panel_bounds.x + maxf((panel_bounds.y - panel_bounds.x - controls_panel.size.y) * 0.5, 0.0)
	return Vector2(open_x if _controls_open else closed_x, centered_y)


func _get_panel_vertical_bounds() -> Vector2:
	var viewport_height: float = get_viewport_rect().size.y
	var top_y: float = SIDE_PANEL_SCREEN_MARGIN
	var bottom_y: float = viewport_height - SIDE_PANEL_SCREEN_MARGIN
	if toolbar_anchor != null:
		top_y = toolbar_anchor.get_global_rect().end.y + SIDE_PANEL_GAP
	if bottom_anchor != null:
		bottom_y = bottom_anchor.get_global_rect().position.y - SIDE_PANEL_GAP
	if bottom_y < top_y:
		var midpoint: float = (top_y + bottom_y) * 0.5
		top_y = midpoint
		bottom_y = midpoint
	return Vector2(top_y, bottom_y)


func _refresh_controls_text() -> void:
	var controls_text := _build_controls_text()
	if controls_label != null:
		controls_label.text = controls_text
	if controls_label_secondary != null:
		controls_label_secondary.text = controls_text


func set_active_build_tool(tool_id: String) -> void:
	_active_build_tool = tool_id
	_update_build_tool_buttons()
	_refresh_controls_text()


func _update_build_tool_buttons() -> void:
	_set_tool_button_state(roads_button, _active_build_tool == BUILD_TOOL_ROADS)
	_set_tool_button_state(zones_button, _active_build_tool == BUILD_TOOL_ZONES)
	_set_tool_button_state(bulldoze_button, _active_build_tool == BUILD_TOOL_BULLDOZE)


func _set_tool_button_state(button: Button, is_active: bool) -> void:
	if button == null:
		return
	button.button_pressed = is_active
	if button is ToolbarButton:
		(button as ToolbarButton).sync_pressed_state()


func update_controls_panel_debug(debug_text: String) -> void:
	if controls_label_secondary == null:
		return
	var controls_text := _build_controls_text()
	if debug_text.is_empty():
		controls_label_secondary.text = controls_text
		return
	controls_label_secondary.text = "%s\n\nDebug\n%s" % [controls_text, debug_text]


func _prepare_intro_state() -> void:
	if toolbar_anchor != null:
		toolbar_anchor.modulate.a = 0.0
		toolbar_anchor.position.y -= 18.0
	for card: Control in bottom_cards:
		card.modulate.a = 0.0
		card.position.y += 24.0


func _play_intro() -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	if toolbar_anchor != null:
		tween.tween_property(toolbar_anchor, "modulate:a", 1.0, UIStyleScript.ANIM_MEDIUM)
		tween.parallel().tween_property(toolbar_anchor, "position:y", toolbar_anchor.position.y + 18.0, UIStyleScript.ANIM_MEDIUM)
	for index: int in range(bottom_cards.size()):
		var card: Control = bottom_cards[index]
		tween.chain().tween_property(card, "modulate:a", 1.0, UIStyleScript.ANIM_FAST)
		tween.parallel().tween_property(card, "position:y", card.position.y - 24.0, UIStyleScript.ANIM_FAST)


func _build_controls_text() -> String:
	match _active_build_tool:
		BUILD_TOOL_ROADS:
			return "LMB build/select  |  Shift+LMB edit\nG move node  |  C curve mode  |  Esc cancel\nWASD or MMB pan  |  RMB rotate  |  Wheel zoom"
		BUILD_TOOL_ZONES:
			return "LMB paint zoning\nEsc cancel zoning action\nWASD or MMB pan  |  RMB rotate  |  Wheel zoom"
		BUILD_TOOL_BULLDOZE:
			return "LMB remove hovered node\nDelete remove selected node\nEsc cancel selection\nWASD or MMB pan  |  RMB rotate  |  Wheel zoom"
		_:
			return "WASD or MMB pan  |  RMB rotate  |  Wheel zoom"
