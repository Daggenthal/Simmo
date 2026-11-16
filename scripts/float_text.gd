class_name FloatText
extends Node2D
## Floating damage numbers and pop-up text (MapleStory style).

var text := ""
var color := Color.WHITE
var life := 0.9
var _t := 0.0
var _label: Label

static func spawn(parent: Node, pos: Vector2, msg: String, col: Color, duration := 0.9) -> FloatText:
	var ft := FloatText.new()
	ft.text = msg
	ft.color = col
	ft.life = duration
	ft.position = pos + Vector2(randf_range(-4, 4), 0)
	ft.z_index = 50
	parent.add_child(ft)
	return ft

func _ready() -> void:
	_label = Label.new()
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 10)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(80, 14)
	_label.position = Vector2(-40, -7)
	add_child(_label)

func _process(delta: float) -> void:
	_t += delta
	position.y -= 28.0 * delta
	modulate.a = clampf(1.0 - (_t / life) ** 2, 0.0, 1.0)
	if _t >= life:
		queue_free()
