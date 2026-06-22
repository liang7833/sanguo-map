@tool
class_name BaseSubEditor extends Control

@export var editor: ProvinceMapEditor

var province_map: ProvinceMap:
	get:
		return editor.province_map

func _enter_tree() -> void:
	editor.province_map_changed.connect(_on_province_map_changed)

func _exit_tree() -> void:
	if editor.province_map_changed.is_connected(_on_province_map_changed):
		editor.province_map_changed.disconnect(_on_province_map_changed)

func _on_province_map_changed() -> void:
	update_display()

# Override in sub-editors to react to province_map changes
func update_display() -> void:
	pass
