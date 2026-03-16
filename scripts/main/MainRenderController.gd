extends RefCounted
class_name MainRenderController

const MainRoadRendererScript = preload("res://scripts/main/MainRoadRenderer.gd")
const MainTerrainRendererScript = preload("res://scripts/main/MainTerrainRenderer.gd")
const MainChunkRendererScript = preload("res://scripts/main/MainChunkRenderer.gd")

var road_renderer: MainRoadRenderer = MainRoadRendererScript.new()
var terrain_renderer: MainTerrainRenderer = MainTerrainRendererScript.new()
var chunk_renderer: MainChunkRenderer = MainChunkRendererScript.new()


func _init() -> void:
	chunk_renderer.setup(road_renderer, terrain_renderer)


func rebuild_chunk_system(main) -> void:
	main.chunk_system = CityChunkSystem.new(main.render_chunk_size, main.simulation_chunk_size, main.network_chunk_size)
	main.chunk_system.rebuild_from_network(main.road_network)


func rebuild_visuals(main) -> void:
	terrain_renderer.clear_chunk_visuals(main)
	main.active_render_chunks.clear()
	main.current_camera_chunk = Vector2i(2147483647, 2147483647)
	main.current_render_radius = -1
	update_visible_chunks(main)


func update_visible_chunks(main) -> void:
	chunk_renderer.update_visible_chunks(main)


func set_wireframe_debug(main, enabled: bool) -> void:
	road_renderer.set_wireframe_debug(main, enabled)


func create_unshaded_material(albedo: Color) -> StandardMaterial3D:
	return road_renderer.create_unshaded_material(albedo)


func create_road_material() -> StandardMaterial3D:
	return road_renderer.create_road_material()


func build_road_mesh_for_segments(main, chunk_segments: Array) -> ArrayMesh:
	return road_renderer.build_road_mesh_for_segments(main, chunk_segments)
