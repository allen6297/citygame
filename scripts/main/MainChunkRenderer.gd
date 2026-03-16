extends RefCounted
class_name MainChunkRenderer

var road_renderer: MainRoadRenderer
var terrain_renderer: MainTerrainRenderer


func setup(road_renderer_ref: MainRoadRenderer, terrain_renderer_ref: MainTerrainRenderer) -> void:
	road_renderer = road_renderer_ref
	terrain_renderer = terrain_renderer_ref


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
	terrain_mesh_instance.mesh = terrain_renderer.build_chunk_terrain_mesh(main)
	terrain_mesh_instance.material_override = terrain_renderer.create_chunk_terrain_material(main)
	terrain_mesh_instance.position = terrain_renderer.get_chunk_center(chunk_coord, main.render_chunk_size)
	chunk_root.add_child(terrain_mesh_instance)

	var render_chunk: CityChunkSystem.RenderChunk = main.chunk_system.get_render_chunk(chunk_coord)
	if render_chunk == null:
		return chunk_root

	var chunk_segments := get_segments_by_ids(main, render_chunk.segment_ids)
	if not chunk_segments.is_empty():
		var road_mesh_instance := MeshInstance3D.new()
		road_mesh_instance.name = "Roads"
		road_mesh_instance.mesh = road_renderer.build_road_mesh_for_segments(main, chunk_segments)
		road_mesh_instance.material_override = road_renderer.create_road_material()
		road_mesh_instance.material_overlay = road_renderer.get_wireframe_overlay_material() if main.wireframe_debug_active else null
		chunk_root.add_child(road_mesh_instance)

	var chunk_nodes := get_nodes_by_ids(main, render_chunk.node_ids)
	if not chunk_nodes.is_empty():
		var node_mesh_instance := MeshInstance3D.new()
		node_mesh_instance.name = "Nodes"
		node_mesh_instance.mesh = road_renderer.build_node_marker_mesh_for_nodes(main, chunk_nodes)
		node_mesh_instance.material_override = road_renderer.create_unshaded_material(Color(0.82, 0.45, 0.18, 1.0))
		chunk_root.add_child(node_mesh_instance)

	return chunk_root


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
