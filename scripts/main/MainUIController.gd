extends RefCounted
class_name MainUIController


func update_zoom_label(main) -> void:
	if main == null or main.main_ui == null:
		return

	var mode_text := "Idle"
	if main.moving_node_id != -1:
		mode_text = "Moving Node"
	elif main.active_build_tool == "roads":
		mode_text = "Placing Nodes"
	elif main.active_build_tool == "zones":
		mode_text = "Zoning"
	elif main.active_build_tool == "bulldoze":
		mode_text = "Bulldoze"

	if main.main_ui.status_label != null:
		main.main_ui.status_label.text = "Zoom %.1fx\nMode: %s" % [main.camera_3d.size, mode_text]

	if main.main_ui.controls_label != null:
		main.main_ui.controls_label.text = main.main_ui._build_controls_text()
	main.main_ui.update_controls_panel_debug(_build_debug_text(main, mode_text))


func _build_debug_text(main, mode_text: String) -> String:
	return "Mode: %s\nTool: %s\nHovered Node: %s\nMoving Node: %s\nCamera Chunk: %s\nWorld Pos: %.2f, %.2f, %.2f" % [
		mode_text,
		main.active_build_tool,
		main.hovered_node_id,
		main.moving_node_id,
		main.current_camera_chunk,
		main.hovered_world_position.x,
		main.hovered_world_position.y,
		main.hovered_world_position.z
	]
