extends RefCounted
class_name MainRoadRenderer

const DEBUG_INTERSECTION_JOINS := true
const DEBUG_SEGMENT_STRIPS := true
const JOIN_EPSILON := 0.0001
const MIN_JOIN_TRIM := 0.1
const FILLET_MAX_HANDLE_FACTOR := 0.5
const FILLET_MIN_HANDLE_FACTOR := 0.25
const FILLET_MIN_POINT_COUNT := 5

var _wireframe_overlay_material: ShaderMaterial


func build_road_mesh_for_segments(main, chunk_segments: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var node_join_lookup: Dictionary = _build_node_join_lookup(main, chunk_segments)

	for segment: RoadNetworkData.RoadSegment in chunk_segments:
		_add_segment_mesh(main, st, segment, node_join_lookup)

	_add_intersection_fills(st, node_join_lookup)

	return st.commit()


func build_node_marker_mesh_for_nodes(main, chunk_nodes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for node: RoadNetworkData.RoadNode in chunk_nodes:
		add_node_marker_quad(main, st, node.position, main.node_marker_radius)

	return st.commit()


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


func set_wireframe_debug(main, enabled: bool) -> void:
	var overlay_material: Material = get_wireframe_overlay_material() if enabled else null
	for chunk_root_variant in main.active_render_chunks.values():
		var chunk_root: Node3D = chunk_root_variant
		if chunk_root == null:
			continue
		var roads_node: MeshInstance3D = chunk_root.get_node_or_null("Roads") as MeshInstance3D
		if roads_node != null:
			roads_node.material_overlay = overlay_material


func get_wireframe_overlay_material() -> ShaderMaterial:
	if _wireframe_overlay_material != null:
		return _wireframe_overlay_material

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, wireframe, cull_disabled, depth_draw_opaque;

uniform vec4 wire_color : source_color = vec4(0.95, 0.45, 0.12, 1.0);

void fragment() {
	ALBEDO = wire_color.rgb;
	ALPHA = wire_color.a;
}
"""
	_wireframe_overlay_material = ShaderMaterial.new()
	_wireframe_overlay_material.shader = shader
	return _wireframe_overlay_material


func get_segment_visual_width(main, segment: RoadNetworkData.RoadSegment) -> float:
	var profile := segment.road_profile
	if profile == null:
		profile = main.default_road_profile
	if profile == null:
		return 4.0
	return max(profile.get_total_width(), 1.0)


func _add_segment_mesh(main, st: SurfaceTool, segment: RoadNetworkData.RoadSegment, node_join_lookup: Dictionary) -> void:
	var points: Array[Vector3] = segment.points.duplicate()
	if points.size() < 2:
		return

	var elevated_points: Array[Vector3] = []
	for point: Vector3 in points:
		elevated_points.append(point + Vector3.UP * main.visual_height_offset)

	var left_points: Array[Vector3] = []
	var right_points: Array[Vector3] = []
	var segment_width: float = get_segment_visual_width(main, segment)
	var point_widths: Array[float] = []
	point_widths.resize(points.size())
	for index in range(points.size()):
		point_widths[index] = segment_width

	var start_join: Dictionary = _get_path_endpoint_join(node_join_lookup, segment, segment.start_node_id)
	var end_join: Dictionary = _get_path_endpoint_join(node_join_lookup, segment, segment.end_node_id)
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
				left_points.append(endpoint_join["left"])
				right_points.append(endpoint_join["right"])
				continue

			var forward: Vector3 = _get_polyline_direction(elevated_points, index)
			if forward.length_squared() <= JOIN_EPSILON:
				forward = Vector3.FORWARD
			var normal: Vector3 = forward.cross(Vector3.UP).normalized()
			if normal.length_squared() <= JOIN_EPSILON:
				normal = Vector3.RIGHT
			left_points.append(point - normal * half_width)
			right_points.append(point + normal * half_width)
			continue

		var incoming: Vector3 = (elevated_points[index] - elevated_points[index - 1]).normalized()
		var outgoing: Vector3 = (elevated_points[index + 1] - elevated_points[index]).normalized()
		if incoming.length_squared() <= JOIN_EPSILON or outgoing.length_squared() <= JOIN_EPSILON:
			var fallback_normal: Vector3 = _get_polyline_direction(elevated_points, index).cross(Vector3.UP).normalized()
			if fallback_normal.length_squared() <= JOIN_EPSILON:
				fallback_normal = Vector3.RIGHT
			left_points.append(point - fallback_normal * half_width)
			right_points.append(point + fallback_normal * half_width)
			continue

		var incoming_normal: Vector3 = incoming.cross(Vector3.UP).normalized()
		var outgoing_normal: Vector3 = outgoing.cross(Vector3.UP).normalized()
		var joined_edges: Dictionary = _build_joined_edge_points(point, half_width, incoming, outgoing, incoming_normal, outgoing_normal)
		left_points.append(joined_edges["left"])
		right_points.append(joined_edges["right"])

	_emit_segment_strip(st, segment.id, left_points, right_points)


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
	var incoming: Vector3 = (points[index] - points[index - 1]).normalized()
	var outgoing: Vector3 = (points[index + 1] - points[index]).normalized()
	var blended: Vector3 = (incoming + outgoing).normalized()
	if blended.length_squared() <= JOIN_EPSILON:
		return outgoing
	return blended


func _get_segment_points_from_node(segment: RoadNetworkData.RoadSegment, from_node_id: int) -> Array[Vector3]:
	if segment.start_node_id == from_node_id:
		return segment.points.duplicate()
	if segment.end_node_id == from_node_id:
		var reversed_points: Array[Vector3] = segment.points.duplicate()
		reversed_points.reverse()
		return reversed_points
	return segment.points.duplicate()


func _emit_segment_strip(st: SurfaceTool, segment_id: int, left_points: Array[Vector3], right_points: Array[Vector3]) -> void:
	if left_points.size() != right_points.size() or left_points.size() < 2:
		return
	if DEBUG_SEGMENT_STRIPS:
		_print_segment_strip_debug(segment_id, left_points, right_points)
	var local_indices: Array[String] = []
	for index in range(1, left_points.size()):
		var base_index: int = (index - 1) * 4
		var start_left: Vector3 = left_points[index - 1]
		var start_right: Vector3 = right_points[index - 1]
		var end_left: Vector3 = left_points[index]
		var end_right: Vector3 = right_points[index]
		add_triangle(st, start_left, start_right, end_right)
		add_triangle(st, start_left, end_right, end_left)
		local_indices.append("[%s,%s,%s] [%s,%s,%s]" % [base_index, base_index + 1, base_index + 3, base_index, base_index + 3, base_index + 2])
	if DEBUG_SEGMENT_STRIPS:
		print("Segment %s strip triangles: %s" % [segment_id, " | ".join(local_indices)])


func _build_joined_edge_points(center: Vector3, half_width: float, incoming: Vector3, outgoing: Vector3, incoming_normal: Vector3, outgoing_normal: Vector3) -> Dictionary:
	var tangent: Vector3 = (incoming + outgoing).normalized()
	if tangent.length_squared() <= JOIN_EPSILON:
		return {"left": center - outgoing_normal * half_width, "right": center + outgoing_normal * half_width}
	var miter: Vector3 = tangent.cross(Vector3.UP).normalized()
	if miter.length_squared() <= JOIN_EPSILON:
		return {"left": center - outgoing_normal * half_width, "right": center + outgoing_normal * half_width}
	var miter_dot: float = absf(miter.dot(incoming_normal))
	if miter_dot <= JOIN_EPSILON:
		return {"left": center - outgoing_normal * half_width, "right": center + outgoing_normal * half_width}
	var miter_length: float = half_width / miter_dot
	if miter_length > half_width * 2.0:
		return {"left": center - outgoing_normal * half_width, "right": center + outgoing_normal * half_width}
	return {"left": center - miter * miter_length, "right": center + miter * miter_length}


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
	for index in range(approaches.size()):
		var road_width: float = float(approaches[index]["half_width"]) * 2.0
		var base_setback: float = min(
			road_width * float(main.intersection_setback_multiplier),
			float(approaches[index]["trim_limit"])
		)
		approaches[index]["left_join"] = Vector3.ZERO
		approaches[index]["right_join"] = Vector3.ZERO
		approaches[index]["center_join"] = Vector3.ZERO
		approaches[index]["left_trim_distance"] = base_setback
		approaches[index]["right_trim_distance"] = base_setback
		approaches[index]["trim_distance"] = base_setback
	var join_by_segment_id: Dictionary = {}
	for index in range(approaches.size()):
		var current: Dictionary = approaches[index]
		var next: Dictionary = approaches[(index + 1) % approaches.size()]
		var corner_requirements: Dictionary = _compute_corner_trim_requirements(current, next, "right_edge_origin", "left_edge_origin")
		approaches[index]["corner_to_next_debug"] = corner_requirements
		approaches[index]["right_trim_distance"] = max(float(approaches[index]["right_trim_distance"]), float(corner_requirements["current_trim"]))
		approaches[(index + 1) % approaches.size()]["left_trim_distance"] = max(float(approaches[(index + 1) % approaches.size()]["left_trim_distance"]), float(corner_requirements["next_trim"]))
	for index in range(approaches.size()):
		var approach: Dictionary = approaches[index]
		var trim_distance: float = min(max(float(approach["left_trim_distance"]), float(approach["right_trim_distance"])), float(approach["trim_limit"]))
		trim_distance = clamp(trim_distance, MIN_JOIN_TRIM * 0.5, float(approach["trim_limit"]))
		approaches[index]["trim_distance"] = trim_distance
		var left_join: Vector3 = approach["left_edge_origin"] + approach["direction"] * trim_distance + Vector3.UP * main.visual_height_offset
		var right_join: Vector3 = approach["right_edge_origin"] + approach["direction"] * trim_distance + Vector3.UP * main.visual_height_offset
		var center_join: Vector3 = (left_join + right_join) * 0.5
		approaches[index]["left_join"] = left_join
		approaches[index]["right_join"] = right_join
		approaches[index]["center_join"] = center_join
		join_by_segment_id[int(approach["segment_id"])] = {"segment_id": int(approach["segment_id"]), "left": left_join, "right": right_join, "center": center_join}
	var corner_entries: Array[Dictionary] = _build_sorted_corner_entries(node.position, approaches)
	if DEBUG_INTERSECTION_JOINS:
		_print_node_join_debug(node, approaches, corner_entries)
	return {
		"node_id": node.id,
		"approaches": approaches,
		"join_by_segment_id": join_by_segment_id,
		"corner_entries": corner_entries,
	}


func _build_segment_approach(main, node: RoadNetworkData.RoadNode, segment: RoadNetworkData.RoadSegment) -> Dictionary:
	var segment_points: Array[Vector3] = _get_segment_points_from_node(segment, node.id)
	if segment_points.size() < 2:
		return {}
	var direction: Vector3 = (segment_points[1] - segment_points[0]).normalized()
	if direction.length_squared() <= JOIN_EPSILON:
		return {}
	var normal: Vector3 = direction.cross(Vector3.UP).normalized()
	if normal.length_squared() <= JOIN_EPSILON:
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
		"left_edge_angle": atan2((node.position - normal * half_width).z - node.position.z, (node.position - normal * half_width).x - node.position.x),
		"right_edge_angle": atan2((node.position + normal * half_width).z - node.position.z, (node.position + normal * half_width).x - node.position.x),
	}


func _get_segment_trim_limit(segment_points: Array[Vector3], width: float) -> float:
	if segment_points.size() < 2:
		return max(width, 0.5)
	var first_leg_length: float = segment_points[0].distance_to(segment_points[1])
	return max(min(width, first_leg_length * 0.45), MIN_JOIN_TRIM)


func _compute_corner_trim_requirements(current: Dictionary, next: Dictionary, current_edge_key: String, next_edge_key: String) -> Dictionary:
	var current_edge_origin: Vector3 = current[current_edge_key]
	var next_edge_origin: Vector3 = next[next_edge_key]
	var current_direction: Vector3 = current["direction"]
	var next_direction: Vector3 = next["direction"]
	var signed_turn: float = _signed_turn_2d(current_direction, next_direction)
	if signed_turn <= 0.0:
		return {
			"current_trim": min(float(current["half_width"]) * 0.5, float(current["trim_limit"])),
			"next_trim": min(float(next["half_width"]) * 0.5, float(next["trim_limit"])),
			"intersection_valid": false,
			"intersection_point": current_edge_origin,
			"step_back_a": current_edge_origin,
			"step_back_b": next_edge_origin,
			"current_edge_key": current_edge_key,
			"next_edge_key": next_edge_key,
		}
	var edge_intersection: Dictionary = _intersect_offset_rays(current_edge_origin, current_direction, next_edge_origin, next_direction)
	if bool(edge_intersection.get("valid", false)):
		var distance_current: float = float(edge_intersection["distance_a"])
		var distance_next: float = float(edge_intersection["distance_b"])
		var current_trim: float = min(float(current["half_width"]), float(current["trim_limit"]))
		var next_trim: float = min(float(next["half_width"]), float(next["trim_limit"]))
		if distance_current > MIN_JOIN_TRIM:
			current_trim = min(current_trim, max(distance_current - MIN_JOIN_TRIM, MIN_JOIN_TRIM))
		else:
			current_trim = min(current_trim, max(distance_current * 0.5, MIN_JOIN_TRIM * 0.5))
		if distance_next > MIN_JOIN_TRIM:
			next_trim = min(next_trim, max(distance_next - MIN_JOIN_TRIM, MIN_JOIN_TRIM))
		else:
			next_trim = min(next_trim, max(distance_next * 0.5, MIN_JOIN_TRIM * 0.5))
		return {
			"current_trim": max(current_trim, MIN_JOIN_TRIM * 0.5),
			"next_trim": max(next_trim, MIN_JOIN_TRIM * 0.5),
			"intersection_valid": true,
			"intersection_point": edge_intersection["point"],
			"step_back_a": current_edge_origin + current_direction * current_trim,
			"step_back_b": next_edge_origin + next_direction * next_trim,
			"current_edge_key": current_edge_key,
			"next_edge_key": next_edge_key,
		}
	var fallback_current_trim: float = min(float(current["half_width"]) * 0.5, float(current["trim_limit"]))
	var fallback_next_trim: float = min(float(next["half_width"]) * 0.5, float(next["trim_limit"]))
	return {
		"current_trim": max(fallback_current_trim, MIN_JOIN_TRIM * 0.5),
		"next_trim": max(fallback_next_trim, MIN_JOIN_TRIM * 0.5),
		"intersection_valid": false,
		"intersection_point": current_edge_origin,
		"step_back_a": current_edge_origin + current_direction * fallback_current_trim,
		"step_back_b": next_edge_origin + next_direction * fallback_next_trim,
		"current_edge_key": current_edge_key,
		"next_edge_key": next_edge_key,
	}


func _intersect_offset_rays(start_a: Vector3, dir_a: Vector3, start_b: Vector3, dir_b: Vector3) -> Dictionary:
	var point_a: Vector2 = Vector2(start_a.x, start_a.z)
	var point_b: Vector2 = Vector2(start_b.x, start_b.z)
	var vector_a: Vector2 = Vector2(dir_a.x, dir_a.z)
	var vector_b: Vector2 = Vector2(dir_b.x, dir_b.z)
	var determinant: float = vector_a.x * vector_b.y - vector_a.y * vector_b.x
	if absf(determinant) <= JOIN_EPSILON:
		return {"valid": false}
	var delta: Vector2 = point_b - point_a
	var distance_a: float = (delta.x * vector_b.y - delta.y * vector_b.x) / determinant
	var distance_b: float = (delta.x * vector_a.y - delta.y * vector_a.x) / determinant
	if distance_a < 0.0 or distance_b < 0.0:
		return {"valid": false}
	return {
		"valid": true,
		"distance_a": distance_a,
		"distance_b": distance_b,
		"point": Vector3(start_a.x + dir_a.x * distance_a, (start_a.y + start_b.y) * 0.5, start_a.z + dir_a.z * distance_a),
	}


func _get_path_endpoint_join(node_join_lookup: Dictionary, segment: RoadNetworkData.RoadSegment, node_id: int) -> Dictionary:
	if not node_join_lookup.has(node_id):
		return {}
	var node_join: Dictionary = node_join_lookup[node_id]
	var join_by_segment_id: Dictionary = node_join.get("join_by_segment_id", {})
	if not join_by_segment_id.has(segment.id):
		return {}
	var endpoint_join: Dictionary = join_by_segment_id[segment.id]
	if segment.start_node_id == node_id:
		return endpoint_join
	return {
		"segment_id": int(endpoint_join.get("segment_id", segment.id)),
		"left": endpoint_join["right"],
		"right": endpoint_join["left"],
		"center": endpoint_join["center"],
	}


func _add_intersection_fills(st: SurfaceTool, node_join_lookup: Dictionary) -> void:
	for node_join_variant in node_join_lookup.values():
		var node_join: Dictionary = node_join_variant
		_add_intersection_fill_for_node_join(st, node_join)


func _add_intersection_fill_for_node_join(st: SurfaceTool, node_join: Dictionary) -> void:
	var approaches: Array[Dictionary] = node_join.get("approaches", [])
	if approaches.size() < 3:
		return
	var raw_perimeter_points: Array[Vector3] = _build_intersection_perimeter_from_curves(node_join)
	var perimeter_points: Array[Vector3] = _ensure_counter_clockwise(_remove_nearly_collinear_points(_dedupe_perimeter_loop(raw_perimeter_points)))
	if DEBUG_INTERSECTION_JOINS:
		_print_intersection_perimeter_debug(int(node_join.get("node_id", -1)), raw_perimeter_points, perimeter_points)
	if perimeter_points.size() < 3:
		return
	var polygon_2d: PackedVector2Array = PackedVector2Array()
	for point: Vector3 in perimeter_points:
		polygon_2d.append(Vector2(point.x, point.z))
	var triangulation: PackedInt32Array = Geometry2D.triangulate_polygon(polygon_2d)
	if triangulation.is_empty():
		_add_intersection_fill_fan_fallback(st, perimeter_points)
		return
	if DEBUG_INTERSECTION_JOINS:
		var triangle_summary: Array[String] = []
		for index in range(0, triangulation.size(), 3):
			triangle_summary.append("[%s,%s,%s]" % [triangulation[index], triangulation[index + 1], triangulation[index + 2]])
		print("Intersection node %s triangulation indices: %s" % [int(node_join.get("node_id", -1)), " | ".join(triangle_summary)])
	for index in range(0, triangulation.size(), 3):
		add_triangle(st, perimeter_points[triangulation[index]], perimeter_points[triangulation[index + 1]], perimeter_points[triangulation[index + 2]])


func _build_intersection_perimeter_from_curves(node_join: Dictionary) -> Array[Vector3]:
	var corner_entries: Array[Dictionary] = node_join.get("corner_entries", [])
	var perimeter_points: Array[Vector3] = []
	if corner_entries.is_empty():
		return perimeter_points
	_append_perimeter_point(perimeter_points, corner_entries[0]["point"])
	for index in range(corner_entries.size()):
		var current_corner: Dictionary = corner_entries[index]
		var next_corner: Dictionary = corner_entries[(index + 1) % corner_entries.size()]
		if int(current_corner["segment_id"]) == int(next_corner["segment_id"]):
			_append_perimeter_point(perimeter_points, next_corner["point"])
			continue
		var curve_points: Array[Vector3] = _build_local_corner_curve(
			0.0,
			current_corner["point"],
			current_corner["direction"],
			next_corner["point"],
			next_corner["direction"]
		)
		_append_curve_segment_to_perimeter(perimeter_points, curve_points)
		_append_perimeter_point(perimeter_points, next_corner["point"])
	return perimeter_points


func _build_local_corner_curve(height_offset: float, fillet_start: Vector3, start_direction: Vector3, fillet_end: Vector3, end_direction: Vector3) -> Array[Vector3]:
	var start_point: Vector3 = fillet_start - Vector3.UP * height_offset
	var end_point: Vector3 = fillet_end - Vector3.UP * height_offset
	return _elevate_curve_points(_sample_corner_fillet(start_point, start_direction, end_point, end_direction), height_offset)


func _build_sorted_corner_entries(node_position: Vector3, approaches: Array[Dictionary]) -> Array[Dictionary]:
	var corner_entries: Array[Dictionary] = []
	for index in range(approaches.size()):
		var current_approach: Dictionary = approaches[index]
		var next_approach: Dictionary = approaches[(index + 1) % approaches.size()]
		var right_point: Vector3 = current_approach["right_join"]
		var left_point: Vector3 = next_approach["left_join"]
		corner_entries.append({
			"segment_id": int(current_approach["segment_id"]),
			"side": "right",
			"point": right_point,
			"direction": current_approach["direction"],
			"angle": atan2(right_point.z - node_position.z, right_point.x - node_position.x),
		})
		corner_entries.append({
			"segment_id": int(next_approach["segment_id"]),
			"side": "left",
			"point": left_point,
			"direction": next_approach["direction"],
			"angle": atan2(left_point.z - node_position.z, left_point.x - node_position.x),
		})
	return corner_entries


func _append_perimeter_point(perimeter_points: Array[Vector3], point: Vector3) -> void:
	if perimeter_points.is_empty() or perimeter_points[perimeter_points.size() - 1].distance_squared_to(point) > 0.0001:
		perimeter_points.append(point)


func _append_curve_segment_to_perimeter(perimeter_points: Array[Vector3], curve_points: Array[Vector3]) -> void:
	if curve_points.is_empty():
		return
	for curve_index in range(1, curve_points.size() - 1):
		_append_perimeter_point(perimeter_points, curve_points[curve_index])


func _dedupe_perimeter_loop(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		if result.is_empty() or result[result.size() - 1].distance_squared_to(point) > 0.0001:
			result.append(point)
	if result.size() >= 2 and result[0].distance_squared_to(result[result.size() - 1]) <= 0.0001:
		result.remove_at(result.size() - 1)
	return result


func _remove_nearly_collinear_points(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 4:
		return points
	var filtered_points: Array[Vector3] = []
	for index in range(points.size()):
		var previous: Vector3 = points[(index - 1 + points.size()) % points.size()]
		var current: Vector3 = points[index]
		var next: Vector3 = points[(index + 1) % points.size()]
		var previous_dir: Vector2 = Vector2(current.x - previous.x, current.z - previous.z)
		var next_dir: Vector2 = Vector2(next.x - current.x, next.z - current.z)
		if previous_dir.length_squared() <= JOIN_EPSILON or next_dir.length_squared() <= JOIN_EPSILON:
			continue
		previous_dir = previous_dir.normalized()
		next_dir = next_dir.normalized()
		var cross_amount: float = absf(previous_dir.x * next_dir.y - previous_dir.y * next_dir.x)
		if cross_amount <= 0.01 and current.distance_to(previous) + current.distance_to(next) >= previous.distance_to(next) - 0.01:
			continue
		filtered_points.append(current)
	if filtered_points.size() >= 3:
		return filtered_points
	return points


func _ensure_counter_clockwise(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 3:
		return points
	var signed_area: float = 0.0
	for index in range(points.size()):
		var current: Vector3 = points[index]
		var next: Vector3 = points[(index + 1) % points.size()]
		signed_area += current.x * next.z - next.x * current.z
	if signed_area >= 0.0:
		return points
	var reversed_points: Array[Vector3] = points.duplicate()
	reversed_points.reverse()
	return reversed_points


func _sample_corner_fillet(start_point: Vector3, start_direction: Vector3, end_point: Vector3, end_direction: Vector3) -> Array[Vector3]:
	var chord_length: float = start_point.distance_to(end_point)
	if chord_length <= 0.001:
		return [start_point, end_point]
	var start_tangent: Vector3 = start_direction.normalized()
	var end_tangent: Vector3 = end_direction.normalized()
	if start_tangent.length_squared() <= JOIN_EPSILON or end_tangent.length_squared() <= JOIN_EPSILON:
		return [start_point, end_point]
	var turn_amount: float = absf(_signed_turn_2d(start_tangent, end_tangent))
	if turn_amount < deg_to_rad(2.0):
		return [start_point, end_point]
	if turn_amount > deg_to_rad(135.0):
		return [start_point, end_point]
	var turn_blend: float = inverse_lerp(deg_to_rad(2.0), PI, turn_amount)
	var handle_factor: float = lerpf(FILLET_MIN_HANDLE_FACTOR, FILLET_MAX_HANDLE_FACTOR, turn_blend)
	var local_radius: float = min(chord_length * 0.65, 8.0)
	var handle_length: float = min(chord_length * handle_factor, local_radius)
	if handle_length <= MIN_JOIN_TRIM * 0.25:
		return [start_point, end_point]
	var control_a: Vector3 = start_point + start_tangent * handle_length
	var control_b: Vector3 = end_point - end_tangent * handle_length
	var curvature_boost: float = 1.0 + turn_blend
	var sample_count: int = maxi(FILLET_MIN_POINT_COUNT, int(ceil((chord_length * curvature_boost) / 0.9)) + 1)
	var result: Array[Vector3] = []
	for sample_index in range(sample_count):
		var t: float = float(sample_index) / float(sample_count - 1)
		result.append(_sample_cubic_bezier(start_point, control_a, control_b, end_point, t))
	return result


func _add_intersection_fill_fan_fallback(st: SurfaceTool, perimeter_points: Array[Vector3]) -> void:
	if perimeter_points.size() < 3:
		return
	var center: Vector3 = Vector3.ZERO
	for point: Vector3 in perimeter_points:
		center += point
	center /= float(perimeter_points.size())
	for index in range(perimeter_points.size()):
		var current: Vector3 = perimeter_points[index]
		var next: Vector3 = perimeter_points[(index + 1) % perimeter_points.size()]
		add_triangle(st, center, current, next)


func _sample_cubic_bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var omt: float = 1.0 - t
	var omt2: float = omt * omt
	var t2: float = t * t
	return a * (omt2 * omt) + b * (3.0 * omt2 * t) + c * (3.0 * omt * t2) + d * (t2 * t)


func _elevate_curve_points(points: Array[Vector3], height_offset: float) -> Array[Vector3]:
	var elevated_points: Array[Vector3] = []
	for point: Vector3 in points:
		elevated_points.append(point + Vector3.UP * height_offset)
	return elevated_points


func _signed_turn_2d(from_direction: Vector3, to_direction: Vector3) -> float:
	var from_2d: Vector2 = Vector2(from_direction.x, from_direction.z).normalized()
	var to_2d: Vector2 = Vector2(to_direction.x, to_direction.z).normalized()
	if from_2d.length_squared() <= JOIN_EPSILON or to_2d.length_squared() <= JOIN_EPSILON:
		return 0.0
	return atan2(from_2d.x * to_2d.y - from_2d.y * to_2d.x, from_2d.dot(to_2d))


func _uses_left_to_right_perimeter(approaches: Array[Dictionary]) -> bool:
	if approaches.is_empty():
		return true
	var left_to_right_score := 0.0
	var right_to_left_score := 0.0
	for approach: Dictionary in approaches:
		var left_angle: float = float(approach["left_edge_angle"])
		var right_angle: float = float(approach["right_edge_angle"])
		left_to_right_score += wrapf(right_angle - left_angle, 0.0, TAU)
		right_to_left_score += wrapf(left_angle - right_angle, 0.0, TAU)
	return left_to_right_score <= right_to_left_score


func _print_node_join_debug(node: RoadNetworkData.RoadNode, approaches: Array[Dictionary], corner_entries: Array[Dictionary]) -> void:
	var approach_summary: Array[String] = []
	for approach: Dictionary in approaches:
		var left_join: Vector3 = approach["left_join"]
		var right_join: Vector3 = approach["right_join"]
		approach_summary.append("seg %s angle %.1f trim %.2f left(%.2f, %.2f) right(%.2f, %.2f)" % [
			int(approach["segment_id"]),
			rad_to_deg(float(approach["angle"])),
			float(approach["trim_distance"]),
			left_join.x,
			left_join.z,
			right_join.x,
			right_join.z,
		])
	print("Intersection node %s order: %s" % [node.id, " | ".join(approach_summary)])
	for approach: Dictionary in approaches:
		var debug_info: Dictionary = approach.get("corner_to_next_debug", {})
		var raw_intersection: Vector3 = debug_info.get("intersection_point", Vector3.ZERO)
		var step_back_a: Vector3 = debug_info.get("step_back_a", Vector3.ZERO)
		var step_back_b: Vector3 = debug_info.get("step_back_b", Vector3.ZERO)
		print("Intersection node %s seg %s -> next raw(%.2f, %.2f) step_a(%.2f, %.2f) step_b(%.2f, %.2f) valid=%s" % [
			node.id,
			int(approach["segment_id"]),
			raw_intersection.x,
			raw_intersection.z,
			step_back_a.x,
			step_back_a.z,
			step_back_b.x,
			step_back_b.z,
			str(debug_info.get("intersection_valid", false)),
		])
	var corner_summary: Array[String] = []
	for corner: Dictionary in corner_entries:
		corner_summary.append(
			"seg %s %s (%.2f, %.2f) angle %.1f" % [
				int(corner["segment_id"]),
				String(corner["side"]),
				corner["point"].x,
				corner["point"].z,
				rad_to_deg(float(corner["angle"])),
			]
		)
	print("Intersection node %s sorted corners: %s" % [node.id, " | ".join(corner_summary)])
	for index in range(corner_entries.size()):
		var current_corner: Dictionary = corner_entries[index]
		var next_corner: Dictionary = corner_entries[(index + 1) % corner_entries.size()]
		if int(current_corner["segment_id"]) == int(next_corner["segment_id"]):
			continue
		var sampled_curve: Array[Vector3] = _sample_corner_fillet(
			current_corner["point"],
			current_corner["direction"],
			next_corner["point"],
			next_corner["direction"]
		)
		var sampled_points: Array[String] = []
		for curve_point: Vector3 in sampled_curve:
			sampled_points.append("(%.2f, %.2f)" % [curve_point.x, curve_point.z])
		print(
			"Corner %s.%s -> %s.%s fillet_start(%.2f, %.2f) fillet_end(%.2f, %.2f) samples: %s" % [
				int(current_corner["segment_id"]),
				String(current_corner["side"]),
				int(next_corner["segment_id"]),
				String(next_corner["side"]),
				current_corner["point"].x,
				current_corner["point"].z,
				next_corner["point"].x,
				next_corner["point"].z,
				" -> ".join(sampled_points),
			]
		)


func _print_intersection_perimeter_debug(node_id: int, raw_points: Array[Vector3], deduped_points: Array[Vector3]) -> void:
	var raw_summary: Array[String] = []
	for point: Vector3 in raw_points:
		raw_summary.append("(%.2f, %.2f)" % [point.x, point.z])
	var deduped_summary: Array[String] = []
	for point: Vector3 in deduped_points:
		deduped_summary.append("(%.2f, %.2f)" % [point.x, point.z])
	print("Intersection node %s perimeter raw: %s" % [node_id, " -> ".join(raw_summary)])
	print("Intersection node %s perimeter deduped: %s" % [node_id, " -> ".join(deduped_summary)])
	print("Intersection node %s triangulation input: %s" % [node_id, " -> ".join(deduped_summary)])


func _print_segment_strip_debug(segment_id: int, left_points: Array[Vector3], right_points: Array[Vector3]) -> void:
	var vertex_summary: Array[String] = []
	for index in range(left_points.size()):
		var left_point: Vector3 = left_points[index]
		var right_point: Vector3 = right_points[index]
		vertex_summary.append("%s:L(%.2f, %.2f) R(%.2f, %.2f)" % [index, left_point.x, left_point.z, right_point.x, right_point.z])
	print("Segment %s strip vertices: %s" % [segment_id, " | ".join(vertex_summary)])
