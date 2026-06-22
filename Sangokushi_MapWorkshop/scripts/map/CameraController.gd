extends Camera2D
class_name CameraController
## 地图摄像机控制器 — 支持鼠标拖拽平移 + 滚轮缩放

@export var min_zoom := 0.25
@export var max_zoom := 2.0
@export var zoom_speed := 0.1
@export var pan_speed := 1.0

var _is_dragging := false
var _drag_start := Vector2.ZERO
var _camera_start := Vector2.ZERO


func _ready() -> void:
	# 居中显示地图
	position = Vector2(720, 700)
	zoom = Vector2(0.5, 0.5)


func _input(event: InputEvent) -> void:
	# 滚轮缩放
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_point(1.0 + zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_point(1.0 - zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_dragging = true
				_drag_start = event.position
				_camera_start = position
			else:
				_is_dragging = false

	# 中键拖拽平移
	if event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.position - _drag_start
		position = _camera_start - delta * pan_speed / zoom


func _zoom_at_point(factor: float, mouse_pos: Vector2) -> void:
	var new_zoom := zoom * factor
	if new_zoom.x < min_zoom or new_zoom.x > max_zoom:
		return

	# 以鼠标位置为中心缩放
	var before := get_global_mouse_position()
	zoom = new_zoom
	var after := get_global_mouse_position()
	position += before - after