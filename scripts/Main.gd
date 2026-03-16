extends Node3D

const BUILD_TOOL_ROADS := "roads"
const BUILD_TOOL_ZONES := "zones"
const BUILD_TOOL_BULLDOZE := "bulldoze"

const MainUIControllerScript = preload("res://scripts/main/MainUIController.gd")
const MainCameraControllerScript = preload("res://scripts/main/MainCameraController.gd")
const MainRenderControllerScript = preload("res://scripts/main/MainRenderController.gd")
const MainRoadEditorScript = preload("res://scripts/main/MainRoadEditor.gd")

@export var road_network: RoadNetworkData
@export var default_road_profile: RoadProfile
@export var render_chunk_size: float = 32.0
@export var simulation_chunk_size: float = 64.0
@export var network_chunk_size: float = 24.0
@export var render_chunk_load_radius: int = 3
@export var render_chunk_load_padding: int = 1
@export var node_marker_radius: float = 0.45
@export var visual_height_offset: float = 0.08
@export var terrain_tile_overlap: float = 0.25
@export var road_snap_distance: float = 2.0
@export var segment_snap_distance: float = 2.5
@export_range(0.0, 90.0, 1.0) var segment_angle_snap_degrees: float = 15.0
@export var camera_pan_speed: float = 30.0
@export var camera_zoom_step: float = 2.5
@export var camera_rotate_step: float = PI * 0.25
@export var camera_tilt_step: float = 5.0
@export var min_camera_size: float = 8.0
@export var max_camera_size: float = 120.0
@export var camera_distance: float = 60.0
@export_range(35.0, 60.0, 1.0) var camera_tilt_degrees: float = 55.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_boom: Node3D = $CameraPivot/CameraBoom
@onready var camera_3d: Camera3D = $CameraPivot/CameraBoom/Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var placement_cursor: MeshInstance3D = $PlacementCursor
@onready var road_chunks: Node3D = $RoadChunks
@onready var main_ui: MainUI = $UI/MainUI

var ui_controller: MainUIController = MainUIControllerScript.new()
var camera_controller: MainCameraController = MainCameraControllerScript.new()
var render_controller: MainRenderController = MainRenderControllerScript.new()
var road_editor: MainRoadEditor = MainRoadEditorScript.new()

var chunk_system: CityChunkSystem
var active_render_chunks: Dictionary = {}
var current_camera_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var current_render_radius: int = -1
var wireframe_debug_active := false
var preview_road: MeshInstance3D
var curve_control_cursor: MeshInstance3D
var hovered_world_position: Vector3 = Vector3.ZERO
var hovered_world_raw_position: Vector3 = Vector3.ZERO
var hovered_node_id: int = -1
var hovered_segment_id: int = -1
var selected_start_node_id: int = -1
var curve_build_enabled := false
var curve_control_set := false
var curve_control_position: Vector3 = Vector3.ZERO
var moving_node_id: int = -1
var moving_node_original_position: Vector3 = Vector3.ZERO
var moving_node_preview_position: Vector3 = Vector3(INF, INF, INF)
var is_panning := false
var is_rotating := false
var active_build_tool := BUILD_TOOL_ROADS


func _ready() -> void:
	if road_network == null:
		road_network = RoadNetworkData.new()

	if default_road_profile == null:
		default_road_profile = _create_default_profile()

	if road_network.nodes.is_empty() and road_network.segments.is_empty():
		_build_sample_network()

	ground.visible = false
	road_editor.setup_visuals(self)
	render_controller.rebuild_chunk_system(self)
	camera_controller.configure_camera(self)
	camera_controller.center_camera_on_network(self)
	render_controller.rebuild_visuals(self)
	if main_ui != null:
		if not main_ui.build_tool_selected.is_connected(_on_build_tool_selected):
			main_ui.build_tool_selected.connect(_on_build_tool_selected)
		main_ui.set_active_build_tool(active_build_tool)
	ui_controller.update_zoom_label(self)
	_print_world_summary()


func _process(delta: float) -> void:
	camera_controller.handle_keyboard_camera_pan(self, delta)
	road_editor.process(self)
	render_controller.update_visible_chunks(self)
	var should_show_wireframe: bool = Input.is_key_pressed(KEY_SPACE)
	if should_show_wireframe != wireframe_debug_active:
		wireframe_debug_active = should_show_wireframe
		render_controller.set_wireframe_debug(self, wireframe_debug_active)
	ui_controller.update_zoom_label(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if camera_controller.handle_mouse_button(self, event):
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if active_build_tool == BUILD_TOOL_ROADS:
				if Input.is_key_pressed(KEY_SHIFT):
					road_editor.handle_edit_click(self)
					return
				if moving_node_id != -1:
					road_editor.finish_node_move(self, true)
					return
				road_editor.handle_build_click(self)
			elif active_build_tool == BUILD_TOOL_BULLDOZE:
				road_editor.remove_hovered_or_selected_node(self)
		return

	if event is InputEventMouseMotion:
		camera_controller.handle_mouse_motion(self, event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if main_ui != null:
			main_ui._unhandled_input(event)
		if camera_controller.handle_key_input(self, event):
			return
		if event.keycode == KEY_ESCAPE:
			if moving_node_id != -1:
				road_editor.finish_node_move(self, false)
			selected_start_node_id = -1
			road_editor.reset_curve_build(self)
			ui_controller.update_zoom_label(self)
		elif event.keycode == KEY_C and active_build_tool == BUILD_TOOL_ROADS:
			road_editor.toggle_curve_build(self)
		elif event.keycode == KEY_G and active_build_tool == BUILD_TOOL_ROADS:
			road_editor.toggle_node_move(self)
		elif (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and active_build_tool != BUILD_TOOL_ZONES:
			road_editor.remove_hovered_or_selected_node(self)


func _on_build_tool_selected(tool_id: String) -> void:
	active_build_tool = tool_id
	selected_start_node_id = -1
	if moving_node_id != -1:
		road_editor.finish_node_move(self, false)
	road_editor.reset_curve_build(self)
	ui_controller.update_zoom_label(self)


func _create_default_profile() -> RoadProfile:
	var profile := RoadProfile.new()
	profile.display_name = "Two-Lane Street"
	profile.lanes_forward = 1
	profile.lanes_backward = 1
	profile.sidewalk_left = 2.0
	profile.sidewalk_right = 2.0
	return profile


func _build_sample_network() -> void:
	var west: RoadNetworkData.RoadNode = road_network.add_node(Vector3(-8.0, 0.0, 0.0))
	var center: RoadNetworkData.RoadNode = road_network.add_node(Vector3(0.0, 0.0, 0.0))
	var east: RoadNetworkData.RoadNode = road_network.add_node(Vector3(8.0, 0.0, 0.0))
	var north: RoadNetworkData.RoadNode = road_network.add_node(Vector3(0.0, 0.0, -8.0))

	road_network.add_segment(west.id, center.id, default_road_profile)
	road_network.add_segment(center.id, east.id, default_road_profile)
	road_network.add_segment(north.id, center.id, default_road_profile)


func _rebuild_world() -> void:
	render_controller.rebuild_chunk_system(self)
	render_controller.rebuild_visuals(self)


func _print_world_summary() -> void:
	print(
		"Road network ready: %s nodes, %s segments, profile width %.2fm" %
		[
			road_network.nodes.size(),
			road_network.segments.size(),
			default_road_profile.get_total_width()
		]
	)

	for segment: RoadNetworkData.RoadSegment in road_network.segments:
		print(
			"Segment %s connects %s -> %s and is %.2fm long" %
			[
				segment.id,
				segment.start_node_id,
				segment.end_node_id,
				road_network.get_segment_length(segment.id)
			]
		)

	if chunk_system != null:
		print(
			"Chunks: %s render, %s simulation, %s network" %
			[
				chunk_system.render_chunks.size(),
				chunk_system.simulation_chunks.size(),
				chunk_system.network_chunks.size()
			]
		)
