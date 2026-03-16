extends RefCounted
class_name MainUIController


func update_zoom_label(main) -> void:
	if main == null or main.main_ui == null:
		return

	var mode_text := "Idle"
	if main.moving_node_id != -1:
		mode_text = "Moving Node"
	elif main.curve_build_enabled:
		mode_text = "Curve Build"
	elif main.selected_start_node_id != -1:
		mode_text = "Building Road"
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
	return "Mode: %s\nTool: %s\nHovered Node: %s\nHovered Segment: %s\nSelected Start: %s\nMoving Node: %s\nCurve Enabled: %s\nCurve Set: %s\nAngle Snap: %.0f deg\nCamera Chunk: %s\nWorld Pos: %.2f, %.2f, %.2f" % [
		mode_text,
		main.active_build_tool,
		main.hovered_node_id,
		main.hovered_segment_id,
		main.selected_start_node_id,
		main.moving_node_id,
		"yes" if main.curve_build_enabled else "no",
		"yes" if main.curve_control_set else "no",
		main.segment_angle_snap_degrees,
		main.current_camera_chunk,
		main.hovered_world_position.x,
		main.hovered_world_position.y,
		main.hovered_world_position.z
	]
