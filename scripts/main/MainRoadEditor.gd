extends RefCounted
class_name MainRoadEditor

const RoadPointScript = preload("res://addons/road-generator/nodes/road_point.gd")


func setup_visuals(main) -> void:
	if main.placement_cursor == null:
		main.placement_cursor = MeshInstance3D.new()
		main.placement_cursor.name = "PlacementCursor"
		main.add_child(main.placement_cursor)

	var cursor_mesh := CylinderMesh.new()
	cursor_mesh.top_radius = 0.55
	cursor_mesh.bottom_radius = 0.55
	cursor_mesh.height = 0.12
	cursor_mesh.radial_segments = 16
	main.placement_cursor.mesh = cursor_mesh
	main.placement_cursor.visible = true
	main.placement_cursor.material_override = main.render_controller.create_unshaded_material(Color(0.25, 0.85, 1.0, 0.8))


func process(main) -> void:
	update_hover_state(main)
	update_node_move(main)
	update_editor_visuals(main)


func handle_build_click(main) -> void:
	if main.moving_node_id != -1:
		return

	var ordered_points: Array = get_ordered_road_points(main)
	if ordered_points.is_empty():
		var road_point = _create_road_point(main, null, get_build_preview_position(main))
		if road_point == null:
			return
		main.hovered_node_id = road_point.get_instance_id()
		main._rebuild_world()
		return

	var last_point = ordered_points[ordered_points.size() - 1]
	var new_point = _create_road_point(main, last_point, get_build_preview_position(main))
	if new_point == null:
		return
	if not last_point.connect_roadpoint(RoadPointScript.PointInit.NEXT, new_point, RoadPointScript.PointInit.PRIOR):
		new_point.queue_free()
		return
	main.hovered_node_id = new_point.get_instance_id()
	main._rebuild_world()


func handle_edit_click(main) -> void:
	if main.moving_node_id != -1:
		return
	if main.hovered_node_id != -1:
		return

	var segment_data: Dictionary = find_nearest_segment_data(main, main.hovered_world_position)
	if segment_data.is_empty():
		return

	var start_point = segment_data["start"]
	var end_point = segment_data["end"]
	var new_point = _create_road_point(main, start_point, main.hovered_world_position)
	if new_point == null:
		return

	start_point.disconnect_roadpoint(RoadPointScript.PointInit.NEXT, RoadPointScript.PointInit.PRIOR)
	var connected_start: bool = start_point.connect_roadpoint(RoadPointScript.PointInit.NEXT, new_point, RoadPointScript.PointInit.PRIOR)
	var connected_end: bool = new_point.connect_roadpoint(RoadPointScript.PointInit.NEXT, end_point, RoadPointScript.PointInit.PRIOR)
	if not connected_start or not connected_end:
		new_point.queue_free()
		main._rebuild_world()
		return

	main.hovered_node_id = new_point.get_instance_id()
	main._rebuild_world()


func remove_hovered_or_selected_node(main) -> void:
	if main.moving_node_id != -1:
		return

	var road_point = find_road_point_by_id(main, main.hovered_node_id)
	if road_point == null:
		return

	var prior_point = road_point.get_prior_road_node(true)
	var next_point = road_point.get_next_road_node(true)

	if prior_point != null:
		road_point.disconnect_roadpoint(RoadPointScript.PointInit.PRIOR, RoadPointScript.PointInit.NEXT)
	if next_point != null:
		road_point.disconnect_roadpoint(RoadPointScript.PointInit.NEXT, RoadPointScript.PointInit.PRIOR)
	if prior_point != null and next_point != null:
		prior_point.connect_roadpoint(RoadPointScript.PointInit.NEXT, next_point, RoadPointScript.PointInit.PRIOR)

	road_point.queue_free()
	main.hovered_node_id = -1
	main._rebuild_world()


func toggle_node_move(main) -> void:
	if main.moving_node_id != -1:
		finish_node_move(main, true)
		return

	var road_point = find_road_point_by_id(main, main.hovered_node_id)
	if road_point == null:
		return

	main.moving_node_id = road_point.get_instance_id()
	main.moving_node_original_position = road_point.global_position
	main.moving_node_preview_position = road_point.global_position


func finish_node_move(main, commit: bool) -> void:
	if main.moving_node_id == -1:
		return

	var road_point = find_road_point_by_id(main, main.moving_node_id)
	if road_point != null and not commit:
		road_point.global_position = main.moving_node_original_position

	main.moving_node_id = -1
	main.moving_node_original_position = Vector3.ZERO
	main.moving_node_preview_position = Vector3(INF, INF, INF)
	main._rebuild_world()


func toggle_curve_build(_main) -> void:
	pass


func reset_curve_build(_main) -> void:
	pass


func update_hover_state(main) -> void:
	var world_hit: Variant = get_mouse_world_position(main)
	if world_hit == null:
		main.hovered_node_id = -1
		main.hovered_segment_id = -1
		return

	main.hovered_world_raw_position = world_hit
	main.hovered_world_position = world_hit
	main.hovered_segment_id = -1

	var road_point = find_nearest_road_point(main, world_hit)
	if road_point != null:
		main.hovered_node_id = road_point.get_instance_id()
		main.hovered_world_position = road_point.global_position
		return

	main.hovered_node_id = -1
	var segment_data: Dictionary = find_nearest_segment_data(main, world_hit)
	if not segment_data.is_empty():
		main.hovered_segment_id = int(segment_data["index"])
		main.hovered_world_position = segment_data["closest"]


func update_node_move(main) -> void:
	if main.moving_node_id == -1:
		return
	if main.moving_node_preview_position.distance_squared_to(main.hovered_world_position) <= 0.0001:
		return

	var road_point = find_road_point_by_id(main, main.moving_node_id)
	if road_point == null:
		return

	main.moving_node_preview_position = main.hovered_world_position
	road_point.global_position = main.hovered_world_position
	main._rebuild_world()


func update_editor_visuals(main) -> void:
	if main.placement_cursor == null:
		return

	main.placement_cursor.visible = true
	main.placement_cursor.position = get_build_preview_position(main) + Vector3.UP * (main.visual_height_offset + 0.06)

	var cursor_color := Color(0.25, 0.85, 1.0, 0.8)
	if main.moving_node_id != -1:
		cursor_color = Color(0.45, 1.0, 0.45, 0.95)
	elif main.hovered_node_id != -1:
		cursor_color = Color(1.0, 0.85, 0.2, 0.9)
	elif main.hovered_segment_id != -1:
		cursor_color = Color(1.0, 0.55, 0.25, 0.9)
	main.placement_cursor.material_override = main.render_controller.create_unshaded_material(cursor_color)


func get_mouse_world_position(main) -> Variant:
	var viewport: Viewport = main.get_viewport()
	var mouse_position: Vector2 = viewport.get_mouse_position()
	var ray_origin: Vector3 = main.camera_3d.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = main.camera_3d.project_ray_normal(mouse_position)
	if main.terrain_3d != null and main.terrain_3d.data != null:
		var terrain_point: Variant = _project_mouse_to_terrain_height(main, ray_origin, ray_direction)
		if terrain_point != null:
			return terrain_point

	var ray_target: Vector3 = ray_origin + ray_direction * 2000.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _collect_road_collision_rids(main.road_manager)
	var space_state: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit["position"]

	if absf(ray_direction.y) < 0.0001:
		return null

	var distance: float = -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + (ray_direction * distance)


func _project_mouse_to_terrain_height(main, ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	var max_distance: float = 2000.0
	var step_count: int = 96
	var previous_point: Vector3 = ray_origin
	var previous_delta: float = previous_point.y - main.terrain_3d.data.get_height(previous_point)

	for step_index in range(1, step_count + 1):
		var t: float = max_distance * float(step_index) / float(step_count)
		var point: Vector3 = ray_origin + (ray_direction * t)
		var terrain_height: float = main.terrain_3d.data.get_height(point)
		var delta: float = point.y - terrain_height
		if delta <= 0.0:
			var refined_point: Vector3 = _refine_terrain_intersection(main, previous_point, point)
			refined_point.y = main.terrain_3d.data.get_height(refined_point)
			return refined_point
		previous_point = point
		previous_delta = delta

	return null


func _refine_terrain_intersection(main, from_point: Vector3, to_point: Vector3) -> Vector3:
	var low: Vector3 = from_point
	var high: Vector3 = to_point
	for _iteration in range(12):
		var midpoint: Vector3 = low.lerp(high, 0.5)
		var terrain_height: float = main.terrain_3d.data.get_height(midpoint)
		if midpoint.y - terrain_height > 0.0:
			low = midpoint
		else:
			high = midpoint
	return low.lerp(high, 0.5)


func _collect_road_collision_rids(root: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if root == null:
		return rids
	_collect_collision_rids_recursive(root, rids)
	return rids


func _collect_collision_rids_recursive(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		rids.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_collision_rids_recursive(child, rids)


func get_build_preview_position(main) -> Vector3:
	return main.hovered_world_position


func get_ordered_road_points(main) -> Array:
	if main.road_container == null:
		return []

	var points: Array = main.road_container.get_roadpoints()
	if points.is_empty():
		return points

	var start_point = points[0].get_last_rp(RoadPointScript.PointInit.PRIOR)
	if start_point == null:
		start_point = points[0]

	var ordered_points: Array = []
	var visited := {}
	var current = start_point
	while current != null and not visited.has(current.get_instance_id()):
		visited[current.get_instance_id()] = true
		ordered_points.append(current)
		current = current.get_next_road_node(true)
	return ordered_points


func find_nearest_road_point(main, world_position: Vector3):
	var snap_limit := get_scaled_snap_distance(main, main.road_snap_distance)
	var best_distance := snap_limit
	var best_point = null
	for road_point in get_ordered_road_points(main):
		var distance: float = road_point.global_position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_point = road_point
	return best_point


func find_nearest_segment_data(main, world_position: Vector3) -> Dictionary:
	var ordered_points: Array = get_ordered_road_points(main)
	if ordered_points.size() < 2:
		return {}

	var snap_limit := get_scaled_snap_distance(main, main.segment_snap_distance)
	var best_distance := snap_limit
	var best_data := {}
	for index in range(1, ordered_points.size()):
		var start_point = ordered_points[index - 1]
		var end_point = ordered_points[index]
		var closest_point := get_closest_point_on_line(start_point.global_position, end_point.global_position, world_position)
		var distance: float = closest_point.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_data = {
				"index": index,
				"start": start_point,
				"end": end_point,
				"closest": closest_point,
			}
	return best_data


func find_road_point_by_id(main, instance_id: int):
	if instance_id == -1:
		return null
	for road_point in get_ordered_road_points(main):
		if road_point.get_instance_id() == instance_id:
			return road_point
	return null


func get_scaled_snap_distance(main, base_distance: float) -> float:
	return max(base_distance, main.camera_3d.size * 0.05)


func get_closest_point_on_line(start: Vector3, end: Vector3, point: Vector3) -> Vector3:
	var segment_vector := end - start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.0001:
		return start

	var weight: float = clamp((point - start).dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	return start + (segment_vector * weight)


func _create_road_point(main, reference_point, position: Vector3):
	if main.road_container == null:
		return null

	var road_point = RoadPointScript.new()
	main.road_container.add_child(road_point)
	if reference_point != null:
		road_point.copy_settings_from(reference_point, false)
	else:
		_configure_default_point(main, road_point)
	road_point.position = main.road_container.to_local(position)
	return road_point


func _configure_default_point(main, road_point) -> void:
	road_point.auto_lanes = true
	road_point.traffic_dir.clear()
	for _lane_index in range(max(main.default_road_profile.lanes_backward, 0)):
		road_point.traffic_dir.append(RoadPointScript.LaneDir.REVERSE)
	for _lane_index in range(max(main.default_road_profile.lanes_forward, 0)):
		road_point.traffic_dir.append(RoadPointScript.LaneDir.FORWARD)
	if road_point.traffic_dir.is_empty():
		road_point.traffic_dir.append(RoadPointScript.LaneDir.BOTH)
	road_point.assign_lanes()
	road_point.lane_width = main.default_road_profile.lane_width
	road_point.shoulder_width_l = main.default_road_profile.sidewalk_left + main.default_road_profile.curb_size
	road_point.shoulder_width_r = main.default_road_profile.sidewalk_right + main.default_road_profile.curb_size
	road_point.gutter_profile = Vector2.ZERO
