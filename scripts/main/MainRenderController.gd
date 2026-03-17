extends RefCounted
class_name MainRenderController

const MainRoadRendererScript = preload("res://scripts/main/MainRoadRenderer.gd")

var road_renderer: MainRoadRenderer = MainRoadRendererScript.new()


func rebuild_chunk_system(_main) -> void:
	pass


func rebuild_visuals(main) -> void:
	if main.road_manager != null:
		main.road_manager.rebuild_all_containers(true)


func update_visible_chunks(_main) -> void:
	pass


func set_wireframe_debug(_main, _enabled: bool) -> void:
	pass


func create_unshaded_material(albedo: Color) -> StandardMaterial3D:
	return road_renderer.create_unshaded_material(albedo)


func create_road_material() -> StandardMaterial3D:
	return road_renderer.create_road_material()


func build_road_mesh_for_segments(main, chunk_segments: Array) -> ArrayMesh:
	return road_renderer.build_road_mesh_for_segments(main, chunk_segments)
