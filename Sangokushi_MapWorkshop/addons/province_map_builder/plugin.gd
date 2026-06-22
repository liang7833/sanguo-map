@tool
extends EditorPlugin


var editor: ProvinceMapEditor
var dock_button: Button

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	editor = preload("res://addons/province_map_builder/editor/province_map_editor.tscn").instantiate()
	editor.undo_redo = get_undo_redo()
	editor.version_label.text = get_plugin_version()
	dock_button = add_control_to_bottom_panel(editor, "Province Map")
	dock_button.visible = false

	add_custom_type("ProvinceMap2D", "Node2D", preload("province_map_2d.gd"), preload("province_map_2d_icon.svg"))


func _exit_tree() -> void:
	remove_control_from_bottom_panel(editor)
	editor.free()

	remove_custom_type("ProvinceMap2D")

func _handles(object: Object) -> bool:
	return object is ProvinceMap

func _make_visible(visible: bool) -> void:
	if visible:
		dock_button.visible = true
		make_bottom_panel_item_visible(editor)
	else:
		dock_button.visible = false
		hide_bottom_panel()

func _edit(object: Object) -> void:
	if object and editor:
		editor.init_editor(object)
