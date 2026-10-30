extends Control

@export var right_side: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func sticker(center: Vector2, dimensions: Vector2, angle: float, paper: Color, words: String, ink: Color, font_size: int = 18) -> void:
	draw_set_transform(center, angle)
	var rect := Rect2(-dimensions / 2.0, dimensions)
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.65))
	draw_rect(rect.grow(2.0), Color("ccc7b6"))
	draw_rect(rect, paper)
	draw_rect(rect.grow(-4.0), ink, false, 1.5)
	var font := ThemeDB.fallback_font
	var text_width := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(-text_width / 2, font_size * 0.34), words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	# Scratches and scuffed corners stay fixed as the window resizes.
	for i in range(8):
		var x := rect.position.x + fmod(float(i * 29 + 7), dimensions.x)
		var y := rect.position.y + fmod(float(i * 17 + 3), dimensions.y)
		draw_line(Vector2(x,y), Vector2(x + 8,y - 1), Color(0.08,0.07,0.06,0.18), 1)

func _draw() -> void:
	if size.x < 60: return
	var scale_factor := clampf(size.x / 390.0, 0.55, 1.3)
	var base_x := size.x / 2.0
	# Different collages at each end, with deliberate overlap and cropped edges.
	sticker(Vector2(base_x - 125 * scale_factor, 22), Vector2(155, 45), -0.13, Color("c3b042"), "NO SIGNAL", Color("171916"), 20)
	sticker(Vector2(base_x + 70 * scale_factor, 10), Vector2(160, 42), 0.10, Color("c8c4af"), "UNDERGROUND", Color("242424"), 17)
	sticker(Vector2(base_x - 15 * scale_factor, 57), Vector2(137, 52), -0.09 if right_side else 0.12, Color("222522"), "SIDE B" if right_side else "STAY LOUD", Color("d9d3b6"), 22)
	sticker(Vector2(base_x + 135 * scale_factor, 72), Vector2(140, 48), -0.20, Color("b45b40"), "AFTER HOURS" if right_side else "LOCAL ONLY", Color("161918"), 16)
	sticker(Vector2(base_x - 140 * scale_factor, 88), Vector2(155, 42), 0.09, Color("b9c2ab"), "EST. 2000" if right_side else "NO SKIPS", Color("181b19"), 20)
	draw_set_transform(Vector2(base_x + 135 * scale_factor, 30), 0.2)
	draw_circle(Vector2.ZERO, 27, Color("dbd4bb"))
	draw_circle(Vector2.ZERO, 23, Color("202421"))
	var bolt := PackedVector2Array([Vector2(1,-19),Vector2(-12,3),Vector2(-1,3),Vector2(-6,19),Vector2(14,-4),Vector2(3,-4)])
	draw_colored_polygon(bolt, Color("bdb04b"))
	draw_set_transform(Vector2(base_x - 85 * scale_factor, 48), -0.15)
	for row in range(3):
		for col in range(6):
			draw_rect(Rect2(col * 7, row * 7, 7, 7), Color("cec9b8") if (row + col) % 2 == 0 else Color("242623"))
	draw_set_transform(Vector2.ZERO)
