extends RefCounted
class_name MainRoadEditor


func setup_visuals(main) -> void:
	var cursor_mesh := CylinderMesh.new()
	cursor_mesh.top_radius = 0.55
	cursor_mesh.bottom_radius = 0.55
	cursor_mesh.height = 0.12
	cursor_mesh.radial_segments = 16
	main.placement_cursor.mesh = cursor_mesh
	main.placement_cursor.visible = true
	main.placement_cursor.material_override = main.render_controller.create_unshaded_material(Color(0.25, 0.85, 1.0, 0.8))

	main.preview_road = MeshInstance3D.new()
	main.preview_road.name = "PreviewRoad"
	main.preview_road.material_override = main.render_controller.create_unshaded_material(Color(0.1, 0.9, 1.0, 0.55))
	main.add_child(main.preview_road)

	main.curve_control_cursor = MeshInstance3D.new()
	main.curve_control_cursor.name = "CurveControlCursor"
	main.curve_control_cursor.mesh = cursor_mesh.duplicate()
	main.curve_control_cursor.visible = false
	main.curve_control_cursor.material_override = main.render_controller.create_unshaded_material(Color(1.0, 0.35, 0.75, 0.9))
	main.add_child(main.curve_control_cursor)


func process(main) -> void:
	update_hover_state(main)
	update_node_move(main)
	update_editor_visuals(main)


func handle_build_click(main) -> void:
	if main.moving_node_id != -1:
		return

	if main.selected_start_node_id == -1:
		var target_node_id: int = resolve_build_target_node(main, false)
		if target_node_id == -1:
			return
		main.selected_start_node_id = target_node_id
		reset_curve_control(main)
		return

	if main.curve_build_enabled and not main.curve_control_set:
		main.curve_control_set = true
		main.curve_control_position = get_curve_control_preview_position(main)
		return

	var target_node_id: int = resolve_build_target_node(main, true)
	if target_node_id == -1:
		return

	if target_node_id == main.selected_start_node_id:
		return

	if not main.road_network.has_segment_between(main.selected_start_node_id, target_node_id):
		var custom_points: Array[Vector3] = []
		if main.curve_build_enabled and main.curve_control_set:
			var start_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.selected_start_node_id)
			var end_node: RoadNetworkData.RoadNode = main.road_network.get_node(target_node_id)
			if start_node != null and end_node != null:
				custom_points = build_curve_points(start_node.position, main.curve_control_position, end_node.position)
		main.road_network.add_segment(main.selected_start_node_id, target_node_id, main.default_road_profile, custom_points)
		main._rebuild_world()
		main.selected_start_node_id = -1
		reset_curve_control(main)
	else:
		main.selected_start_node_id = target_node_id
		reset_curve_control(main)


func handle_edit_click(main) -> void:
	if main.moving_node_id != -1:
		return

	if main.hovered_node_id != -1:
		if main.road_network.combine_segments_at_node(main.hovered_node_id):
			if main.selected_start_node_id == main.hovered_node_id:
				main.selected_start_node_id = -1
			main.hovered_node_id = -1
			main.hovered_segment_id = -1
			main._rebuild_world()
		return

	if main.hovered_segment_id != -1:
		var insert_position: Vector3 = main.hovered_world_position
		var inserted_node: RoadNetworkData.RoadNode = main.road_network.add_node_on_segment(main.hovered_segment_id, insert_position)
		if inserted_node != null:
			main.hovered_node_id = inserted_node.id
			main.hovered_segment_id = -1
			main._rebuild_world()


func remove_hovered_or_selected_node(main) -> void:
	if main.moving_node_id != -1:
		return

	var target_node_id: int = main.hovered_node_id
	if target_node_id == -1:
		target_node_id = main.selected_start_node_id
	if target_node_id == -1:
		return

	if main.road_network.remove_node(target_node_id):
		if main.selected_start_node_id == target_node_id:
			main.selected_start_node_id = -1
		main.hovered_node_id = -1
		main.hovered_segment_id = -1
		main._rebuild_world()


func toggle_node_move(main) -> void:
	if main.moving_node_id != -1:
		finish_node_move(main, true)
		return

	var target_node_id : int = main.hovered_node_id
	if target_node_id == -1:
		target_node_id = main.selected_start_node_id
	if target_node_id == -1:
		return

	var node: RoadNetworkData.RoadNode = main.road_network.get_node(target_node_id)
	if node == null:
		return

	main.moving_node_id = target_node_id
	main.moving_node_original_position = node.position
	main.moving_node_preview_position = node.position
	main.selected_start_node_id = -1
	reset_curve_control(main)


func finish_node_move(main, commit: bool) -> void:
	if main.moving_node_id == -1:
		return

	if not commit:
		main.road_network.move_node(main.moving_node_id, main.moving_node_original_position)

	main.moving_node_id = -1
	main.moving_node_original_position = Vector3.ZERO
	main.moving_node_preview_position = Vector3(INF, INF, INF)
	main._rebuild_world()


func toggle_curve_build(main) -> void:
	main.curve_build_enabled = not main.curve_build_enabled
	reset_curve_control(main)


func reset_curve_build(main) -> void:
	main.curve_build_enabled = false
	reset_curve_control(main)


func reset_curve_control(main) -> void:
	main.curve_control_set = false
	main.curve_control_position = Vector3.ZERO


func update_hover_state(main) -> void:
	var world_hit: Variant = get_mouse_world_position(main)
	if world_hit == null:
		main.hovered_node_id = -1
		main.hovered_segment_id = -1
		return

	main.hovered_world_raw_position = world_hit
	main.hovered_world_position = world_hit
	main.hovered_node_id = find_nearest_node_id(main, world_hit)
	main.hovered_segment_id = -1
	if main.hovered_node_id != -1:
		var hovered_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.hovered_node_id)
		if hovered_node != null:
			main.hovered_world_position = hovered_node.position
	else:
		main.hovered_segment_id = find_nearest_segment_id(main, world_hit)
		if main.hovered_segment_id != -1:
			main.hovered_world_position = get_closest_point_on_segment(main.road_network.get_segment(main.hovered_segment_id), world_hit)


func update_node_move(main) -> void:
	if main.moving_node_id == -1:
		return

	if main.moving_node_preview_position.distance_squared_to(main.hovered_world_position) <= 0.0001:
		return

	main.moving_node_preview_position = main.hovered_world_position
	main.road_network.move_node(main.moving_node_id, main.hovered_world_position)
	main._rebuild_world()


func update_editor_visuals(main) -> void:
	var cursor_world_position: Vector3 = get_cursor_preview_position(main)
	main.placement_cursor.visible = true
	main.placement_cursor.position = cursor_world_position + Vector3.UP * (main.visual_height_offset + 0.06)
	main.curve_control_cursor.visible = main.curve_build_enabled and main.curve_control_set
	if main.curve_control_cursor.visible:
		main.curve_control_cursor.position = main.curve_control_position + Vector3.UP * (main.visual_height_offset + 0.06)

	var cursor_color := Color(0.25, 0.85, 1.0, 0.8)
	if main.moving_node_id != -1:
		cursor_color = Color(0.45, 1.0, 0.45, 0.95)
	elif main.hovered_node_id != -1:
		cursor_color = Color(1.0, 0.85, 0.2, 0.9)
	elif main.hovered_segment_id != -1:
		cursor_color = Color(1.0, 0.55, 0.25, 0.9)
	main.placement_cursor.material_override = main.render_controller.create_unshaded_material(cursor_color)

	main.preview_road.mesh = null
	if main.selected_start_node_id == -1:
		return

	var start_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.selected_start_node_id)
	if start_node == null:
		main.selected_start_node_id = -1
		return

	var preview_end: Vector3 = get_build_preview_position(main)
	if main.hovered_node_id != -1:
		var hovered_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.hovered_node_id)
		if hovered_node != null:
			preview_end = hovered_node.position

	main.preview_road.mesh = main.render_controller.build_road_mesh_for_segments(main, [_create_preview_segment(main, start_node.position, preview_end)])


func resolve_build_target_node(main, allow_segment_insert: bool = true) -> int:
	if main.hovered_node_id != -1:
		return main.hovered_node_id

	if allow_segment_insert and main.hovered_segment_id != -1:
		var insert_position: Vector3 = main.hovered_world_position
		var inserted_node: RoadNetworkData.RoadNode = main.road_network.add_node_on_segment(main.hovered_segment_id, insert_position)
		if inserted_node != null:
			main._rebuild_world()
			return inserted_node.id
		return -1

	var created_node: RoadNetworkData.RoadNode = main.road_network.add_node(get_build_preview_position(main))
	main._rebuild_world()
	return created_node.id


func get_mouse_world_position(main) -> Variant:
	var viewport: Viewport = main.get_viewport()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var ray_origin: Vector3 = main.camera_3d.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = main.camera_3d.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.0001:
		return null

	var distance: float = -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + (ray_direction * distance)


func find_nearest_node_id(main, world_position: Vector3) -> int:
	var snap_limit := get_scaled_snap_distance(main, main.road_snap_distance)
	var best_distance := snap_limit
	var best_id := -1
	for node: RoadNetworkData.RoadNode in main.road_network.nodes:
		var distance := node.position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_id = node.id
	return best_id


func find_nearest_segment_id(main, world_position: Vector3) -> int:
	var snap_limit := get_scaled_snap_distance(main, main.segment_snap_distance)
	var best_distance := snap_limit
	var best_id := -1
	for segment: RoadNetworkData.RoadSegment in main.road_network.segments:
		var closest_point := get_closest_point_on_segment(segment, world_position)
		var distance := closest_point.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_id = segment.id
	return best_id


func get_scaled_snap_distance(main, base_distance: float) -> float:
	return max(base_distance, main.camera_3d.size * 0.05)


func get_cursor_preview_position(main) -> Vector3:
	if main.curve_build_enabled and main.selected_start_node_id != -1 and not main.curve_control_set:
		return get_curve_control_preview_position(main)
	return get_build_preview_position(main)


func get_curve_control_preview_position(main) -> Vector3:
	if main.selected_start_node_id == -1:
		return main.hovered_world_position

	var start_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.selected_start_node_id)
	if start_node == null:
		return main.hovered_world_position
	return get_angle_snapped_position(start_node.position, main.hovered_world_position, main.segment_angle_snap_degrees)


func get_build_preview_position(main) -> Vector3:
	if main.selected_start_node_id == -1:
		return main.hovered_world_position
	if main.hovered_node_id != -1 or main.hovered_segment_id != -1:
		return main.hovered_world_position
	if main.curve_build_enabled and not main.curve_control_set:
		return main.hovered_world_position

	var start_node: RoadNetworkData.RoadNode = main.road_network.get_node(main.selected_start_node_id)
	if start_node == null:
		return main.hovered_world_position
	return get_angle_snapped_position(start_node.position, main.hovered_world_position, main.segment_angle_snap_degrees)


func get_angle_snapped_position(start_position: Vector3, target_position: Vector3, snap_degrees: float) -> Vector3:
	if snap_degrees <= 0.0:
		return target_position

	var planar_offset: Vector3 = target_position - start_position
	planar_offset.y = 0.0
	if planar_offset.length_squared() <= 0.0001:
		return target_position

	var snap_radians: float = deg_to_rad(snap_degrees)
	var angle: float = atan2(planar_offset.z, planar_offset.x)
	var snapped_angle: float = round(angle / snap_radians) * snap_radians
	var snapped_offset: Vector3 = Vector3(cos(snapped_angle), 0.0, sin(snapped_angle)) * planar_offset.length()
	return Vector3(start_position.x + snapped_offset.x, target_position.y, start_position.z + snapped_offset.z)


func get_closest_point_on_segment(segment: RoadNetworkData.RoadSegment, world_position: Vector3) -> Vector3:
	if segment == null or segment.points.size() < 2:
		return world_position

	var best_point := segment.points[0]
	var best_distance := INF
	for index in range(1, segment.points.size()):
		var point := get_closest_point_on_line(segment.points[index - 1], segment.points[index], world_position)
		var distance := point.distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_point = point
	return best_point


func get_closest_point_on_line(start: Vector3, end: Vector3, point: Vector3) -> Vector3:
	var segment_vector := end - start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.0001:
		return start

	var weight: float = clamp((point - start).dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	return start + (segment_vector * weight)


func _create_preview_segment(main, start_position: Vector3, end_position: Vector3) -> RoadNetworkData.RoadSegment:
	var segment := RoadNetworkData.RoadSegment.new()
	segment.road_profile = main.default_road_profile
	if main.curve_build_enabled and main.curve_control_set:
		segment.points = build_curve_points(start_position, main.curve_control_position, end_position)
	else:
		segment.points = [start_position, end_position]
	return segment


func build_curve_points(start_position: Vector3, control_position: Vector3, end_position: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var sample_count := 12
	for index in range(sample_count + 1):
		var t := float(index) / float(sample_count)
		points.append(_sample_quadratic_bezier(start_position, control_position, end_position, t))
	return points


func _sample_quadratic_bezier(start_position: Vector3, control_position: Vector3, end_position: Vector3, t: float) -> Vector3:
	var one_minus_t := 1.0 - t
	return (
		start_position * one_minus_t * one_minus_t
		+ control_position * 2.0 * one_minus_t * t
		+ end_position * t * t
	)
