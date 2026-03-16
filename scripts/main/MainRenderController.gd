extends RefCounted
class_name MainRenderController

const DEBUG_INTERSECTION_JOINS := true


func rebuild_chunk_system(main) -> void:
	main.chunk_system = CityChunkSystem.new(main.render_chunk_size, main.simulation_chunk_size, main.network_chunk_size)
	main.chunk_system.rebuild_from_network(main.road_network)


func rebuild_visuals(main) -> void:
	clear_chunk_visuals(main)
	main.active_render_chunks.clear()
	main.current_camera_chunk = Vector2i(2147483647, 2147483647)
	main.current_render_radius = -1
	update_visible_chunks(main)


func update_visible_chunks(main) -> void:
	if main.chunk_system == null:
		return

	var camera_chunk: Vector2i = get_camera_render_chunk(main)
	var required_radius: int = get_required_render_radius(main)
	if camera_chunk == main.current_camera_chunk and required_radius == main.current_render_radius and not main.active_render_chunks.is_empty():
		return

	main.current_camera_chunk = camera_chunk
	main.current_render_radius = required_radius
	var required_chunks: Dictionary = get_required_render_chunks(camera_chunk, required_radius)

	for chunk_coord in main.active_render_chunks.keys():
		if required_chunks.has(chunk_coord):
			continue
		var chunk_root: Node3D = main.active_render_chunks[chunk_coord]
		chunk_root.queue_free()
		main.active_render_chunks.erase(chunk_coord)

	for chunk_coord in required_chunks.keys():
		if main.active_render_chunks.has(chunk_coord):
			continue
		main.active_render_chunks[chunk_coord] = create_render_chunk_node(main, chunk_coord)


func create_render_chunk_node(main, chunk_coord: Vector2i) -> Node3D:
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%s_%s" % [chunk_coord.x, chunk_coord.y]
	chunk_root.set_meta("chunk_coord", chunk_coord)
	chunk_root.set_meta("chunk_kind", "render")
	main.road_chunks.add_child(chunk_root)

	var terrain_mesh_instance := MeshInstance3D.new()
	terrain_mesh_instance.name = "Terrain"
	terrain_mesh_instance.mesh = build_chunk_terrain_mesh(main)
	terrain_mesh_instance.material_override = create_chunk_terrain_material(main)
	terrain_mesh_instance.position = get_chunk_center(chunk_coord, main.render_chunk_size)
	chunk_root.add_child(terrain_mesh_instance)

	var render_chunk: CityChunkSystem.RenderChunk = main.chunk_system.get_render_chunk(chunk_coord)
	if render_chunk == null:
		return chunk_root

	var chunk_segments := get_segments_by_ids(main, render_chunk.segment_ids)
	if not chunk_segments.is_empty():
		var road_mesh_instance := MeshInstance3D.new()
		road_mesh_instance.name = "Roads"
		road_mesh_instance.mesh = build_road_mesh_for_segments(main, chunk_segments)
		road_mesh_instance.material_override = create_road_material()
		chunk_root.add_child(road_mesh_instance)

	var chunk_nodes := get_nodes_by_ids(main, render_chunk.node_ids)
	if not chunk_nodes.is_empty():
		var node_mesh_instance := MeshInstance3D.new()
		node_mesh_instance.name = "Nodes"
		node_mesh_instance.mesh = build_node_marker_mesh_for_nodes(main, chunk_nodes)
		node_mesh_instance.material_override = create_unshaded_material(Color(0.82, 0.45, 0.18, 1.0))
		chunk_root.add_child(node_mesh_instance)

	return chunk_root


func build_road_mesh_for_segments(main, chunk_segments: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var node_join_lookup: Dictionary = _build_node_join_lookup(main, chunk_segments)

	var render_paths: Array[Dictionary] = _build_render_paths(main, chunk_segments)
	for path: Dictionary in render_paths:
		add_segment_polyline(main, st, path, node_join_lookup)

	_add_intersection_fills(st, node_join_lookup)

	return st.commit()


func build_chunk_terrain_mesh(main) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	var tile_size: float = main.render_chunk_size + main.terrain_tile_overlap
	mesh.size = Vector2(tile_size, tile_size)
	return mesh


func build_node_marker_mesh_for_nodes(main, chunk_nodes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for node: RoadNetworkData.RoadNode in chunk_nodes:
		add_node_marker_quad(main, st, node.position, main.node_marker_radius)

	return st.commit()


func add_segment_polyline(main, st: SurfaceTool, path: Dictionary, node_join_lookup: Dictionary) -> void:
	var points: Array[Vector3] = path.get("points", [])
	var edge_widths: Array[float] = path.get("edge_widths", [])
	if points.size() < 2:
		return

	var elevated_points: Array[Vector3] = []
	for point: Vector3 in points:
		elevated_points.append(point + Vector3.UP * main.visual_height_offset)

	var left_points: Array[Vector3] = []
	var right_points: Array[Vector3] = []
	var point_widths: Array[float] = _build_point_widths(points.size(), edge_widths)
	var start_join: Dictionary = _get_path_endpoint_join(node_join_lookup, int(path.get("start_node_id", -1)), int(path.get("start_segment_id", -1)))
	var end_join: Dictionary = _get_path_endpoint_join(node_join_lookup, int(path.get("end_node_id", -1)), int(path.get("end_segment_id", -1)))
	if not start_join.is_empty():
		elevated_points[0] = start_join["center"]
	if not end_join.is_empty():
		elevated_points[elevated_points.size() - 1] = end_join["center"]

	for index in range(elevated_points.size()):
		var point: Vector3 = elevated_points[index]
		var half_width: float = point_widths[index] * 0.5
		if index == 0 or index == elevated_points.size() - 1:
			var endpoint_join: Dictionary = start_join if index == 0 else end_join
			if not endpoint_join.is_empty():
				if index == 0:
					left_points.append(endpoint_join["left"])
					right_points.append(endpoint_join["right"])
				else:
					# Node-local left/right is defined using the road direction away from the node.
					# At the path end we are traveling into the node, so the strip sides must flip.
					left_points.append(endpoint_join["right"])
					right_points.append(endpoint_join["left"])
				continue

			var forward := _get_polyline_direction(elevated_points, index)
			if forward.length_squared() <= 0.0001:
				forward = Vector3.FORWARD
			var normal := forward.cross(Vector3.UP).normalized()
			if normal.length_squared() <= 0.0001:
				normal = Vector3.RIGHT
			left_points.append(point - normal * half_width)
			right_points.append(point + normal * half_width)
			continue

		var incoming := (elevated_points[index] - elevated_points[index - 1]).normalized()
		var outgoing := (elevated_points[index + 1] - elevated_points[index]).normalized()
		if incoming.length_squared() <= 0.0001 or outgoing.length_squared() <= 0.0001:
			var fallback_normal := _get_polyline_direction(elevated_points, index).cross(Vector3.UP).normalized()
			if fallback_normal.length_squared() <= 0.0001:
				fallback_normal = Vector3.RIGHT
			left_points.append(point - fallback_normal * half_width)
			right_points.append(point + fallback_normal * half_width)
			continue

		var incoming_normal := incoming.cross(Vector3.UP).normalized()
		var outgoing_normal := outgoing.cross(Vector3.UP).normalized()
		var joined_edges: Dictionary = _build_joined_edge_points(
			point,
			half_width,
			incoming,
			outgoing,
			incoming_normal,
			outgoing_normal
		)
		left_points.append(joined_edges["left"])
		right_points.append(joined_edges["right"])

	for index in range(1, left_points.size()):
		add_triangle(st, left_points[index - 1], right_points[index - 1], right_points[index])
		add_triangle(st, left_points[index - 1], right_points[index], left_points[index])


func add_node_marker_quad(main, st: SurfaceTool, center: Vector3, radius: float) -> void:
	center += Vector3.UP * (main.visual_height_offset + 0.01)
	var offset_x := Vector3.RIGHT * radius
	var offset_z := Vector3.FORWARD * radius
	var a := center - offset_x - offset_z
	var b := center + offset_x - offset_z
	var c := center + offset_x + offset_z
	var d := center - offset_x + offset_z

	add_triangle(st, a, b, c)
	add_triangle(st, a, c, d)


func add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)


func _get_polyline_direction(points: Array[Vector3], index: int) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO

	if index == 0:
		return (points[1] - points[0]).normalized()
	if index == points.size() - 1:
		return (points[index] - points[index - 1]).normalized()

	var incoming := (points[index] - points[index - 1]).normalized()
	var outgoing := (points[index + 1] - points[index]).normalized()
	var blended := (incoming + outgoing).normalized()
	if blended.length_squared() <= 0.0001:
		return outgoing
	return blended


func _build_render_paths(main, chunk_segments: Array) -> Array[Dictionary]:
	var segment_lookup: Dictionary = {}
	for segment: RoadNetworkData.RoadSegment in chunk_segments:
		segment_lookup[segment.id] = segment

	var visited: Dictionary = {}
	var paths: Array[Dictionary] = []
	for segment: RoadNetworkData.RoadSegment in chunk_segments:
		if visited.has(segment.id):
			continue
		var path: Dictionary = _build_render_path_from_segment(main, segment, segment_lookup, visited)
		if not path.is_empty():
			paths.append(path)
	return paths


func _build_render_path_from_segment(main, start_segment: RoadNetworkData.RoadSegment, segment_lookup: Dictionary, visited: Dictionary) -> Dictionary:
	visited[start_segment.id] = true
	var points: Array[Vector3] = start_segment.points.duplicate()
	var edge_widths: Array[float] = []
	var start_node_id := start_segment.start_node_id
	var end_node_id := start_segment.end_node_id
	var start_width: float = get_segment_visual_width(main, start_segment)
	for _index in range(start_segment.points.size() - 1):
		edge_widths.append(start_width)

	var backward_extension: Dictionary = _extend_path_from_node(main, start_segment.start_node_id, start_segment.id, segment_lookup, visited, true)
	if not backward_extension.is_empty():
		var backward_points: Array[Vector3] = backward_extension["points"]
		var backward_widths: Array[float] = backward_extension["edge_widths"]
		points = backward_points + points
		edge_widths = backward_widths + edge_widths
		start_node_id = int(backward_extension.get("terminal_node_id", start_node_id))

	var forward_extension: Dictionary = _extend_path_from_node(main, start_segment.end_node_id, start_segment.id, segment_lookup, visited, false)
	if not forward_extension.is_empty():
		var forward_points: Array[Vector3] = forward_extension["points"]
		var forward_widths: Array[float] = forward_extension["edge_widths"]
		points.append_array(forward_points)
		edge_widths.append_array(forward_widths)
		end_node_id = int(forward_extension.get("terminal_node_id", end_node_id))

	return {
		"points": points,
		"edge_widths": edge_widths,
		"start_node_id": start_node_id,
		"end_node_id": end_node_id,
		"start_segment_id": int(backward_extension.get("terminal_segment_id", start_segment.id)) if not backward_extension.is_empty() else start_segment.id,
		"end_segment_id": int(forward_extension.get("terminal_segment_id", start_segment.id)) if not forward_extension.is_empty() else start_segment.id,
	}


func _extend_path_from_node(main, node_id: int, previous_segment_id: int, segment_lookup: Dictionary, visited: Dictionary, prepend: bool) -> Dictionary:
	var collected_points: Array[Vector3] = []
	var collected_widths: Array[float] = []
	var current_node_id: int = node_id
	var current_previous_segment_id: int = previous_segment_id
	var next_segment_id: int = -1

	while true:
		var node: RoadNetworkData.RoadNode = main.road_network.get_node(current_node_id)
		if node == null or node.connected_segment_ids.size() != 2:
			break

		next_segment_id = -1
		for connected_segment_id: int in node.connected_segment_ids:
			if connected_segment_id != current_previous_segment_id and segment_lookup.has(connected_segment_id):
				next_segment_id = connected_segment_id
				break
		if next_segment_id == -1 or visited.has(next_segment_id):
			break

		var next_segment: RoadNetworkData.RoadSegment = segment_lookup[next_segment_id]
		if next_segment == null:
			break

		visited[next_segment_id] = true
		var oriented_points: Array[Vector3] = _get_segment_points_from_node(next_segment, current_node_id)
		if oriented_points.size() < 2:
			break

		var segment_width: float = get_segment_visual_width(main, next_segment)
		if prepend:
			for point_index in range(oriented_points.size() - 1, 0, -1):
				collected_points.push_front(oriented_points[point_index])
			for _width_index in range(oriented_points.size() - 1):
				collected_widths.push_front(segment_width)
		else:
			for point_index in range(1, oriented_points.size()):
				collected_points.append(oriented_points[point_index])
			for _width_index in range(oriented_points.size() - 1):
				collected_widths.append(segment_width)

		current_previous_segment_id = next_segment_id
		if next_segment.end_node_id == current_node_id:
			current_node_id = next_segment.start_node_id
		else:
			current_node_id = next_segment.end_node_id

	return {
		"points": collected_points,
		"edge_widths": collected_widths,
		"terminal_node_id": current_node_id,
		"terminal_segment_id": current_previous_segment_id,
	}


func _get_segment_points_from_node(segment: RoadNetworkData.RoadSegment, from_node_id: int) -> Array[Vector3]:
	if segment.start_node_id == from_node_id:
		return segment.points.duplicate()
	if segment.end_node_id == from_node_id:
		var reversed_points: Array[Vector3] = segment.points.duplicate()
		reversed_points.reverse()
		return reversed_points
	return segment.points.duplicate()


func _build_point_widths(point_count: int, edge_widths: Array[float]) -> Array[float]:
	var point_widths: Array[float] = []
	if point_count <= 0:
		return point_widths
	if edge_widths.is_empty():
		for _index in range(point_count):
			point_widths.append(4.0)
		return point_widths

	point_widths.resize(point_count)
	point_widths[0] = edge_widths[0]
	point_widths[point_count - 1] = edge_widths[edge_widths.size() - 1]
	for index in range(1, point_count - 1):
		point_widths[index] = (edge_widths[index - 1] + edge_widths[mini(index, edge_widths.size() - 1)]) * 0.5
	return point_widths


func _build_joined_edge_points(
	center: Vector3,
	half_width: float,
	incoming: Vector3,
	outgoing: Vector3,
	incoming_normal: Vector3,
	outgoing_normal: Vector3
) -> Dictionary:
	var left_point: Vector3 = _intersect_offset_edges(
		center - incoming_normal * half_width,
		incoming,
		center - outgoing_normal * half_width,
		outgoing
	)
	var right_point: Vector3 = _intersect_offset_edges(
		center + incoming_normal * half_width,
		incoming,
		center + outgoing_normal * half_width,
		outgoing
	)
	return {
		"left": left_point,
		"right": right_point,
	}


func _intersect_offset_edges(start_a: Vector3, dir_a: Vector3, start_b: Vector3, dir_b: Vector3) -> Vector3:
	var point_a := Vector2(start_a.x, start_a.z)
	var point_b := Vector2(start_b.x, start_b.z)
	var vector_a := Vector2(dir_a.x, dir_a.z)
	var vector_b := Vector2(dir_b.x, dir_b.z)
	var determinant: float = vector_a.x * vector_b.y - vector_a.y * vector_b.x
	if absf(determinant) <= 0.0001:
		return Vector3(
			(start_a.x + start_b.x) * 0.5,
			(start_a.y + start_b.y) * 0.5,
			(start_a.z + start_b.z) * 0.5
		)

	var delta: Vector2 = point_b - point_a
	var distance_a: float = (delta.x * vector_b.y - delta.y * vector_b.x) / determinant
	return Vector3(
		start_a.x + dir_a.x * distance_a,
		(start_a.y + start_b.y) * 0.5,
		start_a.z + dir_a.z * distance_a
	)


func _build_node_join_lookup(main, chunk_segments: Array) -> Dictionary:
	var node_lookup: Dictionary = {}
	for segment: RoadNetworkData.RoadSegment in chunk_segments:
		node_lookup[segment.start_node_id] = true
		node_lookup[segment.end_node_id] = true

	var result: Dictionary = {}
	for node_id_variant in node_lookup.keys():
		var node_id: int = int(node_id_variant)
		var node: RoadNetworkData.RoadNode = main.road_network.get_node(node_id)
		if node == null or node.connected_segment_ids.size() <= 2:
			continue

		var join_data: Dictionary = _build_node_join_data(main, node)
		if not join_data.is_empty():
			result[node_id] = join_data

	return result


func _build_node_join_data(main, node: RoadNetworkData.RoadNode) -> Dictionary:
	var approaches: Array[Dictionary] = []
	for segment_id: int in node.connected_segment_ids:
		var segment: RoadNetworkData.RoadSegment = main.road_network.get_segment(segment_id)
		if segment == null:
			continue

		var approach: Dictionary = _build_segment_approach(main, node, segment)
		if not approach.is_empty():
			approaches.append(approach)

	if approaches.size() <= 2:
		return {}

	approaches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["angle"]) < float(b["angle"])
	)

	var join_by_segment_id: Dictionary = {}
	for index in range(approaches.size()):
		var previous: Dictionary = approaches[(index - 1 + approaches.size()) % approaches.size()]
		var current: Dictionary = approaches[index]
		var next: Dictionary = approaches[(index + 1) % approaches.size()]
		# Approaches are sorted by angle. For that winding, the gap between previous->current
		# meets current's left edge, while the gap between current->next meets current's right edge.
		var left_join: Vector3 = _build_node_corner_point(node.position, previous, "right_edge_origin", current, "left_edge_origin")
		var right_join: Vector3 = _build_node_corner_point(node.position, current, "right_edge_origin", next, "left_edge_origin")
		var center_join: Vector3 = (left_join + right_join) * 0.5
		var join: Dictionary = {
			"segment_id": int(current["segment_id"]),
			"left": left_join + Vector3.UP * main.visual_height_offset,
			"right": right_join + Vector3.UP * main.visual_height_offset,
			"center": center_join + Vector3.UP * main.visual_height_offset,
		}
		approaches[index]["left_join"] = join["left"]
		approaches[index]["right_join"] = join["right"]
		approaches[index]["center_join"] = join["center"]
		join_by_segment_id[int(current["segment_id"])] = join

	if DEBUG_INTERSECTION_JOINS:
		_print_node_join_debug(node, approaches)

	return {
		"node_id": node.id,
		"approaches": approaches,
		"join_by_segment_id": join_by_segment_id,
	}


func _build_segment_approach(main, node: RoadNetworkData.RoadNode, segment: RoadNetworkData.RoadSegment) -> Dictionary:
	var segment_points: Array[Vector3] = _get_segment_points_from_node(segment, node.id)
	if segment_points.size() < 2:
		return {}

	var direction: Vector3 = (segment_points[1] - segment_points[0]).normalized()
	if direction.length_squared() <= 0.0001:
		return {}

	var normal: Vector3 = direction.cross(Vector3.UP).normalized()
	if normal.length_squared() <= 0.0001:
		return {}

	var width: float = get_segment_visual_width(main, segment)
	var half_width: float = width * 0.5
	var trim_limit: float = _get_segment_trim_limit(segment_points, width)
	return {
		"segment_id": segment.id,
		"direction": direction,
		"angle": atan2(direction.z, direction.x),
		"half_width": half_width,
		"trim_limit": trim_limit,
		"left_edge_origin": node.position - normal * half_width,
		"right_edge_origin": node.position + normal * half_width,
	}


func _get_segment_trim_limit(segment_points: Array[Vector3], width: float) -> float:
	if segment_points.size() < 2:
		return max(width, 0.5)

	var first_leg_length: float = segment_points[0].distance_to(segment_points[1])
	return max(min(width, first_leg_length * 0.45), 0.25)


func _build_node_corner_point(
	node_position: Vector3,
	first_approach: Dictionary,
	first_key: String,
	second_approach: Dictionary,
	second_key: String
) -> Vector3:
	var first_intersection: Dictionary = _intersect_offset_rays(
		first_approach[first_key],
		first_approach["direction"],
		second_approach[second_key],
		second_approach["direction"]
	)
	if bool(first_intersection["valid"]):
		var first_distance: float = float(first_intersection["distance_a"])
		var second_distance: float = float(first_intersection["distance_b"])
		if first_distance >= 0.0 and second_distance >= 0.0 and first_distance <= float(first_approach["trim_limit"]) and second_distance <= float(second_approach["trim_limit"]):
			return first_intersection["point"]

	var fallback_distance: float = min(float(first_approach["trim_limit"]), float(second_approach["trim_limit"]))
	var first_point: Vector3 = first_approach[first_key] + first_approach["direction"] * fallback_distance
	var second_point: Vector3 = second_approach[second_key] + second_approach["direction"] * fallback_distance
	var fallback_point: Vector3 = (first_point + second_point) * 0.5
	fallback_point.y = node_position.y
	return fallback_point


func _intersect_offset_rays(start_a: Vector3, dir_a: Vector3, start_b: Vector3, dir_b: Vector3) -> Dictionary:
	var point_a: Vector2 = Vector2(start_a.x, start_a.z)
	var point_b: Vector2 = Vector2(start_b.x, start_b.z)
	var vector_a: Vector2 = Vector2(dir_a.x, dir_a.z)
	var vector_b: Vector2 = Vector2(dir_b.x, dir_b.z)
	var determinant: float = vector_a.x * vector_b.y - vector_a.y * vector_b.x
	if absf(determinant) <= 0.0001:
		return {
			"valid": false,
		}

	var delta: Vector2 = point_b - point_a
	var distance_a: float = (delta.x * vector_b.y - delta.y * vector_b.x) / determinant
	var distance_b: float = (delta.x * vector_a.y - delta.y * vector_a.x) / determinant
	return {
		"valid": true,
		"distance_a": distance_a,
		"distance_b": distance_b,
		"point": Vector3(
			start_a.x + dir_a.x * distance_a,
			(start_a.y + start_b.y) * 0.5,
			start_a.z + dir_a.z * distance_a
		),
	}


func _get_path_endpoint_join(node_join_lookup: Dictionary, node_id: int, segment_id: int) -> Dictionary:
	if not node_join_lookup.has(node_id):
		return {}
	var node_join: Dictionary = node_join_lookup[node_id]
	var join_by_segment_id: Dictionary = node_join.get("join_by_segment_id", {})
	if not join_by_segment_id.has(segment_id):
		return {}
	return join_by_segment_id[segment_id]


func _add_intersection_fills(st: SurfaceTool, node_join_lookup: Dictionary) -> void:
	for node_join_variant in node_join_lookup.values():
		var node_join: Dictionary = node_join_variant
		_add_intersection_fill_for_node_join(st, node_join)


func _add_intersection_fill_for_node_join(st: SurfaceTool, node_join: Dictionary) -> void:
	var approaches: Array[Dictionary] = node_join.get("approaches", [])
	if approaches.size() < 3:
		return

	var perimeter_points: Array[Vector3] = []
	for approach: Dictionary in approaches:
		var left_point: Vector3 = approach["left_join"]
		if perimeter_points.is_empty() or perimeter_points[perimeter_points.size() - 1].distance_squared_to(left_point) > 0.0001:
			perimeter_points.append(left_point)
		var right_point: Vector3 = approach["right_join"]
		if perimeter_points.is_empty() or perimeter_points[perimeter_points.size() - 1].distance_squared_to(right_point) > 0.0001:
			perimeter_points.append(right_point)

	if perimeter_points.size() >= 2 and perimeter_points[0].distance_squared_to(perimeter_points[perimeter_points.size() - 1]) <= 0.0001:
		perimeter_points.remove_at(perimeter_points.size() - 1)
	if perimeter_points.size() < 3:
		return

	var center: Vector3 = _compute_polygon_center(perimeter_points)
	for index in range(perimeter_points.size()):
		var current_point: Vector3 = perimeter_points[index]
		var next_point: Vector3 = perimeter_points[(index + 1) % perimeter_points.size()]
		add_triangle(st, center, current_point, next_point)


func _compute_polygon_center(points: Array[Vector3]) -> Vector3:
	var center: Vector3 = Vector3.ZERO
	for point: Vector3 in points:
		center += point
	return center / float(points.size())


func _print_node_join_debug(node: RoadNetworkData.RoadNode, approaches: Array[Dictionary]) -> void:
	var approach_summary: Array[String] = []
	for approach: Dictionary in approaches:
		var left_join: Vector3 = approach["left_join"]
		var right_join: Vector3 = approach["right_join"]
		approach_summary.append(
			"seg %s angle %.1f left(%.2f, %.2f) right(%.2f, %.2f)" % [
				int(approach["segment_id"]),
				rad_to_deg(float(approach["angle"])),
				left_join.x,
				left_join.z,
				right_join.x,
				right_join.z,
			]
		)
	print("Intersection node %s order: %s" % [node.id, " | ".join(approach_summary)])


func get_segment_visual_width(main, segment: RoadNetworkData.RoadSegment) -> float:
	var profile := segment.road_profile
	if profile == null:
		profile = main.default_road_profile

	if profile == null:
		return 4.0

	return max(profile.get_total_width(), 1.0)


func create_unshaded_material(albedo: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func create_road_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.13, 1.0)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func create_chunk_terrain_material(main) -> Material:
	if main.ground.material_override != null:
		return main.ground.material_override

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.33, 0.45, 0.31, 1.0)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func clear_chunk_visuals(main) -> void:
	for child: Node in main.road_chunks.get_children():
		child.queue_free()


func get_segments_by_ids(main, segment_ids: Array[int]) -> Array[RoadNetworkData.RoadSegment]:
	var result: Array[RoadNetworkData.RoadSegment] = []
	for segment_id in segment_ids:
		var segment: RoadNetworkData.RoadSegment = main.road_network.get_segment(segment_id)
		if segment != null:
			result.append(segment)
	return result


func get_nodes_by_ids(main, node_ids: Array[int]) -> Array[RoadNetworkData.RoadNode]:
	var result: Array[RoadNetworkData.RoadNode] = []
	for node_id in node_ids:
		var node: RoadNetworkData.RoadNode = main.road_network.get_node(node_id)
		if node != null:
			result.append(node)
	return result


func get_chunk_center(chunk_coord: Vector2i, chunk_size: float) -> Vector3:
	return Vector3((float(chunk_coord.x) + 0.5) * chunk_size, 0.0, (float(chunk_coord.y) + 0.5) * chunk_size)


func get_camera_render_chunk(main) -> Vector2i:
	return main.road_network.get_chunk_coord(main.camera_pivot.position, main.render_chunk_size)


func get_required_render_chunks(center_chunk: Vector2i, radius: int) -> Dictionary:
	var required := {}
	for chunk_x in range(center_chunk.x - radius, center_chunk.x + radius + 1):
		for chunk_y in range(center_chunk.y - radius, center_chunk.y + radius + 1):
			required[Vector2i(chunk_x, chunk_y)] = true
	return required


func get_required_render_radius(main) -> int:
	var viewport_size: Vector2 = main.get_viewport().get_visible_rect().size
	var aspect_ratio: float = 1.0
	if viewport_size.y > 0.0:
		aspect_ratio = viewport_size.x / viewport_size.y

	var tilt_radians: float = deg_to_rad(main.camera_tilt_degrees)
	var half_height: float = main.camera_3d.size * 0.5
	var half_width: float = half_height * aspect_ratio
	var half_depth_on_ground: float = half_height / max(cos(tilt_radians), 0.2)
	var farthest_extent: float = max(half_width, half_depth_on_ground)
	var dynamic_radius: int = int(ceil(farthest_extent / main.render_chunk_size))
	return max(main.render_chunk_load_radius, dynamic_radius + main.render_chunk_load_padding)
