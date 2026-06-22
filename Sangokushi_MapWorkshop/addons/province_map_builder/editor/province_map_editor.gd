@tool
class_name ProvinceMapEditor extends Control


@export var version_label: Control
var undo_redo: EditorUndoRedoManager

var province_map: ProvinceMap:
	set(value):
		province_map = value
		province_map_changed.emit()
		if province_map and not province_map.changed.is_connected(_on_province_map_changed):
			province_map.changed.connect(_on_province_map_changed)

signal province_map_changed


func init_editor(_province_map: ProvinceMap) -> void:
	province_map = _province_map


func _on_province_map_changed() -> void:
	province_map_changed.emit()
