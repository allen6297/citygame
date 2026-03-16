extends RefCounted
class_name MainCameraController


func configure_camera(main) -> void:
	main.camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	main.camera_3d.size = 32.0
	main.camera_3d.near = 0.1
	main.camera_3d.far = 500.0
	main.camera_pivot.rotation = Vector3.ZERO
	main.camera_boom.rotation = Vector3.ZERO
	apply_camera_tilt(main)


func center_camera_on_network(main) -> void:
	if main.road_network.nodes.is_empty():
		main.camera_pivot.position = Vector3.ZERO
		return

	var minimum: Vector3 = main.road_network.nodes[0].position
	var maximum: Vector3 = main.road_network.nodes[0].position
	for node: RoadNetworkData.RoadNode in main.road_network.nodes:
		minimum = minimum.min(node.position)
		maximum = maximum.max(node.position)

	main.camera_pivot.position = (minimum + maximum) * 0.5

	var span: Vector3 = maximum - minimum
	var largest_span: float = max(span.x, span.z)
	main.camera_3d.size = clamp(max(largest_span * 0.75, main.min_camera_size), main.min_camera_size, main.max_camera_size)
	apply_camera_tilt(main)


func handle_keyboard_camera_pan(main, delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vector.y += 1.0

	if input_vector == Vector2.ZERO:
		return

	var zoom_scale: float = max(main.camera_3d.size / 24.0, 0.35)
	pan_camera(main, input_vector.normalized() * main.camera_pan_speed * zoom_scale * delta)


func handle_mouse_button(main, event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom_camera(main, -main.camera_zoom_step)
		return true
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom_camera(main, main.camera_zoom_step)
		return true
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		main.is_panning = event.pressed
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT:
		main.is_rotating = event.pressed
		return true
	return false


func handle_mouse_motion(main, event: InputEventMouseMotion) -> void:
	if main.is_panning:
		var zoom_scale: float = max(main.camera_3d.size / 24.0, 0.35)
		pan_camera(main, Vector2(-event.relative.x, -event.relative.y) * 0.08 * zoom_scale)

	if main.is_rotating:
		main.camera_pivot.rotate_y(-event.relative.x * 0.008)


func handle_key_input(main, event: InputEventKey) -> bool:
	if event.keycode == KEY_Q:
		main.camera_pivot.rotate_y(-main.camera_rotate_step)
		return true
	if event.keycode == KEY_E:
		main.camera_pivot.rotate_y(main.camera_rotate_step)
		return true
	if event.keycode == KEY_R:
		main.camera_tilt_degrees = clamp(main.camera_tilt_degrees - main.camera_tilt_step, 35.0, 60.0)
		apply_camera_tilt(main)
		return true
	if event.keycode == KEY_F:
		main.camera_tilt_degrees = clamp(main.camera_tilt_degrees + main.camera_tilt_step, 35.0, 60.0)
		apply_camera_tilt(main)
		return true
	if event.keycode == KEY_MINUS:
		zoom_camera(main, main.camera_zoom_step)
		return true
	if event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
		zoom_camera(main, -main.camera_zoom_step)
		return true
	return false


func pan_camera(main, amount: Vector2) -> void:
	var right: Vector3 = main.camera_pivot.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var forward: Vector3 = main.camera_pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	main.camera_pivot.position += (right * amount.x) + (forward * amount.y)


func zoom_camera(main, amount: float) -> void:
	main.camera_3d.size = clamp(main.camera_3d.size + amount, main.min_camera_size, main.max_camera_size)
	apply_camera_tilt(main)


func apply_camera_tilt(main) -> void:
	var tilt_degrees: float = clamp(main.camera_tilt_degrees, 35.0, 60.0)
	var elevation_degrees: float = 90.0 - tilt_degrees
	var elevation_radians: float = deg_to_rad(elevation_degrees)
	var boom_distance: float = get_camera_boom_distance(main, tilt_degrees)
	var vertical_distance: float = sin(elevation_radians) * boom_distance
	var horizontal_distance: float = cos(elevation_radians) * boom_distance

	main.camera_3d.position = Vector3(0.0, vertical_distance, horizontal_distance)
	main.camera_3d.rotation = Vector3(-elevation_radians, 0.0, 0.0)


func get_camera_boom_distance(main, tilt_degrees: float) -> float:
	var viewport_size: Vector2 = main.get_viewport().get_visible_rect().size
	var aspect_ratio: float = 1.0
	if viewport_size.y > 0.0:
		aspect_ratio = viewport_size.x / viewport_size.y

	var tilt_radians: float = deg_to_rad(tilt_degrees)
	var half_height: float = main.camera_3d.size * 0.5
	var half_width: float = half_height * aspect_ratio
	var farthest_extent: float = max(half_height, half_width)
	var zoom_distance: float = farthest_extent / max(sin(tilt_radians), 0.25)
	return max(main.camera_distance, zoom_distance + 8.0)
