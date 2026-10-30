extends Node3D

var dragging := false
var rotation_speed := 0.005


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var viewport_height := get_viewport().get_visible_rect().size.y
				var above_scroll_strip: bool = event.position.y < viewport_height - 100.0
				dragging = above_scroll_strip and mouse_is_over_case(event.position)
			else:
				dragging = false

	if event is InputEventMouseMotion and dragging:
		# Stop if the button was released outside the window.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dragging = false
			return

		rotate_y(event.relative.x * rotation_speed)


func mouse_is_over_case(mouse_position: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var ray_start := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)

	var inverse_transform := global_transform.affine_inverse()
	var local_start := inverse_transform * ray_start
	var local_direction := inverse_transform.basis * ray_direction

	return get_aabb().intersects_ray(
		local_start,
		local_direction
	) != null


# Bounds come from the editable body; the subtraction stays inside these bounds.
func get_aabb() -> AABB:
	var body: CSGMesh3D = get_node("Shape/Body") as CSGMesh3D
	return body.transform * body.mesh.get_aabb()
