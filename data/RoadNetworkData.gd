extends Resource
class_name RoadNetworkData


class RoadNode extends RefCounted:
	var id: int
	var position: Vector3
	var connected_segment_ids: Array[int] = []


class RoadSegment extends Resource:
	var id: int
	var start_node_id: int
	var end_node_id: int

	var override_material: bool = false
	var material_name: String = ""
	var override_lanes: bool = false

	var lane_count_forward: int = 1
	var lane_count_backward: int = 1
	var points: Array[Vector3] = []
	var road_profile: RoadProfile

	func get_lane_count_forward() -> int:
		if override_lanes or road_profile == null:
			return lane_count_forward
		return road_profile.lanes_forward

	func get_lane_count_backward() -> int:
		if override_lanes or road_profile == null:
			return lane_count_backward
		return road_profile.lanes_backward


var nodes: Array[RoadNode] = []
var segments: Array[RoadSegment] = []
var lanes: Array = []
var lane_connections: Array = []
var node_map: Dictionary[int, RoadNode] = {}
var segment_map: Dictionary[int, RoadSegment] = {}


func clear() -> void:
	nodes.clear()
	segments.clear()
	lanes.clear()
	lane_connections.clear()
	node_map.clear()
	segment_map.clear()


func add_node(position: Vector3) -> RoadNode:
	var node := RoadNode.new()
	node.id = _get_next_node_id()
	node.position = position
	nodes.append(node)
	node_map[node.id] = node
	return node


func get_node(node_id: int) -> RoadNode:
	return node_map.get(node_id, null)


func has_node(node_id: int) -> bool:
	return node_map.has(node_id)


func add_segment(start_node_id: int, end_node_id: int, road_profile: RoadProfile, custom_points: Array[Vector3] = []) -> RoadSegment:
	if start_node_id == end_node_id:
		push_error("Cannot create segment from a node to itself.")
		return null

	if road_profile == null:
		push_error("Cannot add segment without a road profile.")
		return null

	var start_node := get_node(start_node_id)
	var end_node := get_node(end_node_id)
	if start_node == null or end_node == null:
		push_error("Cannot add segment with missing node ids.")
		return null

	var segment := RoadSegment.new()
	segment.id = _get_next_segment_id()
	segment.start_node_id = start_node_id
	segment.end_node_id = end_node_id
	segment.road_profile = road_profile
	segment.points = custom_points.duplicate()

	if segment.points.is_empty():
		segment.points = [start_node.position, end_node.position]
	else:
		segment.points[0] = start_node.position
		segment.points[segment.points.size() - 1] = end_node.position

	segments.append(segment)
	segment_map[segment.id] = segment
	start_node.connected_segment_ids.append(segment.id)
	end_node.connected_segment_ids.append(segment.id)
	return segment


func has_segment_between(start_node_id: int, end_node_id: int) -> bool:
	for segment: RoadSegment in segments:
		var matches_forward := segment.start_node_id == start_node_id and segment.end_node_id == end_node_id
		var matches_backward := segment.start_node_id == end_node_id and segment.end_node_id == start_node_id
		if matches_forward or matches_backward:
			return true
	return false


func move_node(node_id: int, new_position: Vector3) -> void:
	var node := get_node(node_id)
	if node == null:
		return

	node.position = new_position

	for segment in get_segments_for_node(node_id):
		if segment.points.is_empty():
			continue
		if segment.start_node_id == node_id:
			segment.points[0] = new_position
		if segment.end_node_id == node_id:
			segment.points[segment.points.size() - 1] = new_position


func get_segment(segment_id: int) -> RoadSegment:
	return segment_map.get(segment_id, null)


func get_segments_for_node(node_id: int) -> Array[RoadSegment]:
	var result: Array[RoadSegment] = []
	var node := get_node(node_id)
	if node == null:
		return result

	for segment_id in node.connected_segment_ids:
		var segment := get_segment(segment_id)
		if segment != null:
			result.append(segment)
	return result


func get_segment_length(segment_id: int) -> float:
	var segment := get_segment(segment_id)
	if segment == null or segment.points.size() < 2:
		return 0.0

	var total_length := 0.0
	for index in range(1, segment.points.size()):
		total_length += segment.points[index - 1].distance_to(segment.points[index])
	return total_length


func get_node_chunks(chunk_size: float) -> Dictionary:
	var result := {}
	if chunk_size <= 0.0:
		return result

	for node: RoadNode in nodes:
		var chunk := get_chunk_coord(node.position, chunk_size)
		if not result.has(chunk):
			result[chunk] = []
		result[chunk].append(node)

	return result


func get_segment_chunks(chunk_size: float) -> Dictionary:
	var result := {}
	if chunk_size <= 0.0:
		return result

	for segment: RoadSegment in segments:
		if segment.points.size() < 2:
			continue

		for chunk in get_segment_chunk_coords(segment, chunk_size):
			if not result.has(chunk):
				result[chunk] = []
			result[chunk].append(segment)

	return result


func remove_segment(segment_id: int) -> bool:
	for index in range(segments.size()):
		var segment := segments[index]
		if segment.id != segment_id:
			continue

		var start_node := get_node(segment.start_node_id)
		var end_node := get_node(segment.end_node_id)
		if start_node != null:
			start_node.connected_segment_ids.erase(segment_id)
		if end_node != null:
			end_node.connected_segment_ids.erase(segment_id)

		segments.remove_at(index)
		segment_map.erase(segment_id)
		return true

	return false


func remove_node(node_id: int) -> bool:
	var node := get_node(node_id)
	if node == null:
		return false

	var connected_segments := get_segments_for_node(node_id)
	if connected_segments.size() == 2:
		return combine_segments_at_node(node_id)

	for segment: RoadSegment in connected_segments:
		remove_segment(segment.id)

	nodes.erase(node)
	node_map.erase(node_id)
	return true


func split_segment(segment_id: int, split_position: Vector3) -> RoadNode:
	return add_node_on_segment(segment_id, split_position)


func add_node_on_segment(segment_id: int, split_position: Vector3) -> RoadNode:
	var segment := get_segment(segment_id)
	if segment == null or segment.points.size() < 2:
		return null

	var start_node := get_node(segment.start_node_id)
	var end_node := get_node(segment.end_node_id)
	if start_node == null or end_node == null:
		return null

	var split_data := _build_split_point_arrays(segment, split_position)
	if split_data.is_empty():
		return null

	var profile := segment.road_profile
	var first_points: Array[Vector3] = split_data["first_points"]
	var second_points: Array[Vector3] = split_data["second_points"]
	remove_segment(segment_id)

	var split_node: RoadNode = add_node(split_data["split_position"])
	add_segment(start_node.id, split_node.id, profile, first_points)
	add_segment(split_node.id, end_node.id, profile, second_points)
	return split_node


func combine_segments_at_node(node_id: int) -> bool:
	var node := get_node(node_id)
	if node == null:
		return false

	var connected_segments := get_segments_for_node(node_id)
	if connected_segments.size() != 2:
		return false

	var first_segment := connected_segments[0]
	var second_segment := connected_segments[1]
	var first_other_id := _get_other_node_id(first_segment, node_id)
	var second_other_id := _get_other_node_id(second_segment, node_id)
	if first_other_id == -1 or second_other_id == -1 or first_other_id == second_other_id:
		return false
	if not _can_combine_segments(first_segment, second_segment):
		return false
	if has_segment_between(first_other_id, second_other_id):
		return false

	var combined_profile := first_segment.road_profile
	var combined_points := _build_combined_segment_points(first_segment, second_segment, first_other_id, second_other_id)
	if combined_points.size() < 2:
		return false

	var merged_segment := _create_merged_segment(first_segment, first_other_id, second_other_id, combined_points)
	if merged_segment == null:
		return false

	remove_segment(first_segment.id)
	remove_segment(second_segment.id)
	nodes.erase(node)
	node_map.erase(node_id)
	segments.append(merged_segment)
	segment_map[merged_segment.id] = merged_segment

	var start_node := get_node(first_other_id)
	var end_node := get_node(second_other_id)
	if start_node != null:
		start_node.connected_segment_ids.append(merged_segment.id)
	if end_node != null:
		end_node.connected_segment_ids.append(merged_segment.id)

	return true


func _get_next_node_id() -> int:
	var max_id := -1
	for node in nodes:
		max_id = max(max_id, node.id)
	return max_id + 1


func _get_next_segment_id() -> int:
	var max_id := -1
	for segment in segments:
		max_id = max(max_id, segment.id)
	return max_id + 1


func get_chunk_coord(position: Vector3, chunk_size: float) -> Vector2i:
	if chunk_size <= 0.0:
		return Vector2i.ZERO

	return Vector2i(
		int(floor(position.x / chunk_size)),
		int(floor(position.z / chunk_size))
	)


func get_segment_chunk_coords(segment: RoadSegment, chunk_size: float) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	if segment.points.is_empty() or chunk_size <= 0.0:
		return coords

	var min_x := segment.points[0].x
	var max_x := segment.points[0].x
	var min_z := segment.points[0].z
	var max_z := segment.points[0].z

	for point: Vector3 in segment.points:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_z = min(min_z, point.z)
		max_z = max(max_z, point.z)

	var min_chunk_x := int(floor(min_x / chunk_size))
	var max_chunk_x := int(floor(max_x / chunk_size))
	var min_chunk_z := int(floor(min_z / chunk_size))
	var max_chunk_z := int(floor(max_z / chunk_size))

	for chunk_x in range(min_chunk_x, max_chunk_x + 1):
		for chunk_z in range(min_chunk_z, max_chunk_z + 1):
			coords.append(Vector2i(chunk_x, chunk_z))

	return coords


func _get_other_node_id(segment: RoadSegment, node_id: int) -> int:
	if segment.start_node_id == node_id:
		return segment.end_node_id
	if segment.end_node_id == node_id:
		return segment.start_node_id
	return -1


func _build_split_point_arrays(segment: RoadSegment, split_position: Vector3) -> Dictionary:
	var best_index := -1
	var best_distance := INF
	var best_split_position := split_position

	for index in range(1, segment.points.size()):
		var closest_point := _get_closest_point_on_line(segment.points[index - 1], segment.points[index], split_position)
		var distance := closest_point.distance_squared_to(split_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
			best_split_position = closest_point

	if best_index == -1:
		return {}

	var first_points: Array[Vector3] = []
	for index in range(best_index):
		first_points.append(segment.points[index])
	first_points.append(best_split_position)

	var second_points: Array[Vector3] = [best_split_position]
	for index in range(best_index, segment.points.size()):
		second_points.append(segment.points[index])

	first_points = _dedupe_adjacent_points(first_points)
	second_points = _dedupe_adjacent_points(second_points)
	if first_points.size() < 2 or second_points.size() < 2:
		return {}

	return {
		"split_position": best_split_position,
		"first_points": first_points,
		"second_points": second_points
	}


func _build_combined_segment_points(first_segment: RoadSegment, second_segment: RoadSegment, start_node_id: int, end_node_id: int) -> Array[Vector3]:
	var start_node := get_node(start_node_id)
	var end_node := get_node(end_node_id)
	if start_node == null or end_node == null:
		return []

	return [start_node.position, end_node.position]


func _can_combine_segments(first_segment: RoadSegment, second_segment: RoadSegment) -> bool:
	return (
		first_segment.road_profile == second_segment.road_profile
		and first_segment.override_material == second_segment.override_material
		and first_segment.material_name == second_segment.material_name
		and first_segment.override_lanes == second_segment.override_lanes
		and first_segment.lane_count_forward == second_segment.lane_count_forward
		and first_segment.lane_count_backward == second_segment.lane_count_backward
	)


func _create_merged_segment(source_segment: RoadSegment, start_node_id: int, end_node_id: int, points: Array[Vector3]) -> RoadSegment:
	var start_node := get_node(start_node_id)
	var end_node := get_node(end_node_id)
	if start_node == null or end_node == null or points.size() < 2:
		return null

	var segment := RoadSegment.new()
	segment.id = _get_next_segment_id()
	segment.start_node_id = start_node_id
	segment.end_node_id = end_node_id
	segment.road_profile = source_segment.road_profile
	segment.override_material = source_segment.override_material
	segment.material_name = source_segment.material_name
	segment.override_lanes = source_segment.override_lanes
	segment.lane_count_forward = source_segment.lane_count_forward
	segment.lane_count_backward = source_segment.lane_count_backward
	segment.points = points.duplicate()
	segment.points[0] = start_node.position
	segment.points[segment.points.size() - 1] = end_node.position
	return segment


func _dedupe_adjacent_points(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		if result.is_empty() or result[result.size() - 1].distance_squared_to(point) > 0.0001:
			result.append(point)
	return result


func _get_closest_point_on_line(start: Vector3, end: Vector3, point: Vector3) -> Vector3:
	var segment_vector := end - start
	var segment_length_squared := segment_vector.length_squared()
	if segment_length_squared <= 0.0001:
		return start

	var weight: float = clamp((point - start).dot(segment_vector) / segment_length_squared, 0.0, 1.0)
	return start + (segment_vector * weight)
