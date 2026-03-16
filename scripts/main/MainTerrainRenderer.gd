extends RefCounted
class_name MainTerrainRenderer


func build_chunk_terrain_mesh(main) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	var tile_size: float = main.render_chunk_size + main.terrain_tile_overlap
	mesh.size = Vector2(tile_size, tile_size)
	return mesh


func create_chunk_terrain_material(main) -> Material:
	if main.ground.material_override != null:
		return main.ground.material_override

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.33, 0.45, 0.31, 1.0)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func get_chunk_center(chunk_coord: Vector2i, chunk_size: float) -> Vector3:
	return Vector3((float(chunk_coord.x) + 0.5) * chunk_size, 0.0, (float(chunk_coord.y) + 0.5) * chunk_size)


func clear_chunk_visuals(main) -> void:
	for child: Node in main.road_chunks.get_children():
		child.queue_free()
