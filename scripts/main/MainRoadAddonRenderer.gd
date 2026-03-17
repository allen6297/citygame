extends RefCounted
class_name MainRoadAddonRenderer

const RoadManagerScript = preload("res://addons/road-generator/nodes/road_manager.gd")
const RoadContainerScript = preload("res://addons/road-generator/nodes/road_container.gd")
const RoadPointScript = preload("res://addons/road-generator/nodes/road_point.gd")
const RoadSurfaceMaterial = preload("res://addons/road-generator/resources/road_texture.material")


func rebuild_roads(main) -> void:
	var roads_root := _get_or_create_roads_root(main)
	for child in roads_root.get_children():
		child.queue_free()

	if main.road_network == null or main.road_network.nodes.size() < 2:
		return

	var road_manager = RoadManagerScript.new()
	road_manager.name = "RoadManager"
	road_manager.auto_refresh = false
	road_manager.material_resource = RoadSurfaceMaterial
	road_manager.density = 2.0
	roads_root.add_child(road_manager)

	var container := _build_container_from_nodes(main)
	if container != null:
		road_manager.add_child(container)

	road_manager.rebuild_all_containers(true)


func _get_or_create_roads_root(main) -> Node3D:
	var roads_root: Node3D = main.get_node_or_null("AddonRoads") as Node3D
	if roads_root != null:
		return roads_root

	roads_root = Node3D.new()
	roads_root.name = "AddonRoads"
	main.add_child(roads_root)
	return roads_root


func _build_container_from_nodes(main) -> Node3D:
	if main.road_network == null or main.road_network.nodes.size() < 2:
		return null

	var road_profile: RoadProfile = main.default_road_profile
	if road_profile == null:
		return null

	var container = RoadContainerScript.new()
	container.name = "RoadPath"
	container.material_resource = RoadSurfaceMaterial
	container.flatten_terrain = false
	container.generate_ai_lanes = false
	container.create_edge_curves = false
	container.debug = false

	var road_points: Array = []
	for point_index in range(main.road_network.nodes.size()):
		var network_node: RoadNetworkData.RoadNode = main.road_network.nodes[point_index]
		var point: Vector3 = network_node.position + Vector3.UP * main.visual_height_offset
		var road_point = RoadPointScript.new()
		road_point.name = "RP_%03d" % point_index
		_configure_road_point(road_point, road_profile)
		road_point.position = point
		road_point.basis = Basis.from_euler(Vector3(0.0, _get_point_yaw(main.road_network.nodes, point_index), 0.0))
		road_point.prior_mag = 0.0
		road_point.next_mag = 0.0
		container.add_child(road_point)
		road_points.append(road_point)

	for point_index in range(road_points.size() - 1):
		var current = road_points[point_index]
		var next = road_points[point_index + 1]
		current.next_pt_init = current.get_path_to(next)
		next.prior_pt_init = next.get_path_to(current)

	return container


func _configure_road_point(road_point, road_profile: RoadProfile) -> void:
	road_point.auto_lanes = true
	road_point.traffic_dir.clear()
	for direction in _build_traffic_dirs(road_profile):
		road_point.traffic_dir.append(direction)
	road_point.assign_lanes()
	road_point.lane_width = road_profile.lane_width
	road_point.shoulder_width_l = road_profile.sidewalk_left + road_profile.curb_size
	road_point.shoulder_width_r = road_profile.sidewalk_right + road_profile.curb_size
	road_point.gutter_profile = Vector2.ZERO
	road_point.alignment = RoadPointScript.Alignment.GEOMETRIC
	road_point.flatten_terrain = false
	road_point.create_geo = true


func _build_traffic_dirs(road_profile: RoadProfile) -> Array:
	var directions: Array = []
	for _lane_index in range(max(road_profile.lanes_backward, 0)):
		directions.append(RoadPointScript.LaneDir.REVERSE)
	for _lane_index in range(max(road_profile.lanes_forward, 0)):
		directions.append(RoadPointScript.LaneDir.FORWARD)
	if directions.is_empty():
		directions.append(RoadPointScript.LaneDir.BOTH)
	return directions


func _get_point_yaw(nodes: Array, point_index: int) -> float:
	var direction := Vector3.ZERO
	if point_index == 0:
		direction = (nodes[1].position - nodes[0].position).normalized()
	elif point_index == nodes.size() - 1:
		direction = (nodes[point_index].position - nodes[point_index - 1].position).normalized()
	else:
		var incoming: Vector3 = (nodes[point_index].position - nodes[point_index - 1].position).normalized()
		var outgoing: Vector3 = (nodes[point_index + 1].position - nodes[point_index].position).normalized()
		direction = (incoming + outgoing).normalized()
		if direction.length_squared() <= 0.0001:
			direction = outgoing

	if direction.length_squared() <= 0.0001:
		return 0.0
	return atan2(direction.x, direction.z)
