@tool
class_name LayerEditor extends BaseSubEditor

# Expected exports (wire in editor):
#   notice_control: Control — shown when no map is loaded yet (hide when layers exist)
#   load_image_button: Button — inside notice_control; opens a file dialog to pick an image
#   image_drop_area: Control — any Control node used as the drag-and-drop target for images
#   display: ProvinceMapDisplay — the canvas for this tab (hidden in edit mode)
#   polygon_edit_display: RegionPolygonEditDisplay — layer polygon edit canvas (hidden by default)
#   edit_layer_button: Button — toggles layer polygon edit mode
#   layer_tree: Tree — shows layers as a hierarchy; configure with hide_root=true, select_mode=Single
#   add_layer_button: Button — opens the subdivision generator to create and add a new child layer
#   remove_layer_button: Button — removes the last layer (only enabled when selected layer has no child)
#   rename_layer_button: Button — renames selected layer via a popup dialog
#   subdivide_button: Button — opens the subdivision generator window for the selected layer
#   subdivision_generator_scene: PackedScene — the LayerSubdivisionGenerator window scene

@export var notice_control: Control
@export var load_image_button: Button
@export var image_drop_area: Control
@export var display: ProvinceMapDisplay
@export var polygon_edit_display: RegionPolygonEditDisplay
@export var edit_layer_button: Button
@export var layer_tree: Tree
@export var add_layer_button: Button
@export var remove_layer_button: Button
@export var rename_layer_button: Button
@export var subdivide_button: Button
@export var subdivision_generator_scene: PackedScene

signal layer_selected(layer_index: int)

var _selected_index: int = -1
var _editing_layer: bool = false
var _generator: SubdivisionGenerator
# Holds the new MapLayer being previewed in the generator before it is inserted into the map.
# Null when the generator is open for re-subdivision of an existing layer.
var _pending_new_layer: MapLayer = null

var _add_pressed: Callable
var _remove_pressed: Callable
var _rename_pressed: Callable
var _subdivide_pressed: Callable
var _item_selected: Callable
var _edit_layer_pressed: Callable
var _vertex_group_moved: Callable
var _vertex_inserted: Callable
var _vertex_deleted: Callable
var _load_image_pressed: Callable

# Rename dialog — created programmatically so no .tscn needed
var _rename_dialog: AcceptDialog
var _rename_line_edit: LineEdit

# File dialog for image selection — created programmatically
var _file_dialog: FileDialog


func _enter_tree() -> void:
	super._enter_tree()

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename Layer"
	_rename_dialog.min_size = Vector2i(300, 80)
	_rename_line_edit = LineEdit.new()
	_rename_dialog.add_child(_rename_line_edit)
	add_child(_rename_dialog)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.bmp,*.webp,*.svg ; Image Files"])
	_file_dialog.min_size = Vector2i(600, 400)
	add_child(_file_dialog)
	_file_dialog.file_selected.connect(_on_image_file_selected)

	_add_pressed = _on_add_pressed
	_remove_pressed = _on_remove_pressed
	_rename_pressed = _on_rename_pressed
	_subdivide_pressed = _on_subdivide_pressed
	_item_selected = _on_item_selected
	_load_image_pressed = _on_load_image_pressed

	if add_layer_button:
		add_layer_button.pressed.connect(_add_pressed)
	if remove_layer_button:
		remove_layer_button.pressed.connect(_remove_pressed)
		remove_layer_button.icon = get_theme_icon("Remove", "EditorIcons")
	if rename_layer_button:
		rename_layer_button.pressed.connect(_rename_pressed)
		rename_layer_button.icon = get_theme_icon("Rename", "EditorIcons")
	if subdivide_button:
		subdivide_button.pressed.connect(_subdivide_pressed)
	if layer_tree:
		layer_tree.item_selected.connect(_item_selected)
	if load_image_button:
		load_image_button.pressed.connect(_load_image_pressed)
	if image_drop_area:
		image_drop_area.set_drag_forwarding(Callable(), _can_drop_image, _drop_image)

	_edit_layer_pressed = _on_edit_layer_pressed
	_vertex_group_moved = _on_vertex_group_moved
	_vertex_inserted = _on_vertex_inserted
	_vertex_deleted = _on_vertex_deleted

	if edit_layer_button:
		edit_layer_button.pressed.connect(_edit_layer_pressed)
		edit_layer_button.text = "Edit"
		edit_layer_button.icon = get_theme_icon("Edit", "EditorIcons")
	if polygon_edit_display:
		polygon_edit_display.vertex_group_moved.connect(_vertex_group_moved)
		polygon_edit_display.vertex_inserted.connect(_vertex_inserted)
		polygon_edit_display.vertex_deleted.connect(_vertex_deleted)


func _exit_tree() -> void:
	super._exit_tree()
	if add_layer_button:
		add_layer_button.pressed.disconnect(_add_pressed)
	if remove_layer_button:
		remove_layer_button.pressed.disconnect(_remove_pressed)
	if rename_layer_button:
		rename_layer_button.pressed.disconnect(_rename_pressed)
	if subdivide_button:
		subdivide_button.pressed.disconnect(_subdivide_pressed)
	if layer_tree:
		layer_tree.item_selected.disconnect(_item_selected)
	if load_image_button:
		load_image_button.pressed.disconnect(_load_image_pressed)
	if image_drop_area:
		image_drop_area.set_drag_forwarding(Callable(), Callable(), Callable())
	if edit_layer_button:
		edit_layer_button.pressed.disconnect(_edit_layer_pressed)
	if polygon_edit_display:
		polygon_edit_display.vertex_group_moved.disconnect(_vertex_group_moved)
		polygon_edit_display.vertex_inserted.disconnect(_vertex_inserted)
		polygon_edit_display.vertex_deleted.disconnect(_vertex_deleted)
	if _generator:
		_generator.queue_free()
		_generator = null


func update_display() -> void:
	if not province_map:
		return
	if display:
		display.province_map = province_map
	var has_map: bool = not province_map.layers.is_empty()
	if notice_control:
		notice_control.visible = not has_map
	if display and not _editing_layer:
		display.visible = has_map
	if not layer_tree:
		return
	layer_tree.clear()
	var hidden_root: TreeItem = layer_tree.create_item()
	var prev_item: TreeItem = hidden_root
	for i: int in range(province_map.layers.size()):
		var layer: MapLayer = province_map.layers[i]
		var label: String = layer.name
		if i == 0:
			label += " (base)"
		var item: TreeItem = layer_tree.create_item(prev_item)
		item.set_text(0, label)
		item.set_metadata(0, i)
		prev_item = item
	# "+" action item — sibling of the base layer so it stays at root indent,
	# always visible regardless of tree collapse state.
	var can_add: bool = not province_map.layers.is_empty()
	var add_item: TreeItem = layer_tree.create_item(hidden_root)
	add_item.set_text(0, "Add Layer")
	add_item.set_icon(0, get_theme_icon("Add", "EditorIcons"))
	add_item.set_metadata(0, -1)
	add_item.set_selectable(0, can_add)
	if not can_add:
		add_item.set_custom_color(0, get_theme_color("disabled_font_color", "Editor"))
	# Auto-select first layer if nothing selected yet
	if _selected_index < 0 and not province_map.layers.is_empty():
		_selected_index = 0
		layer_selected.emit(0)
	# Restore selection if still valid
	if _selected_index >= 0 and _selected_index < province_map.layers.size():
		_select_layer_item(_selected_index)
	else:
		_selected_index = -1
	_update_button_states()
	_sync_display_layer()
	_sync_polygon_edit_display()


func _on_item_selected() -> void:
	if not layer_tree:
		return
	var item: TreeItem = layer_tree.get_selected()
	if not item:
		return
	if item.get_metadata(0) == -1:
		# "+" item — restore real selection and open the generator
		if _selected_index >= 0 and _selected_index < (province_map.layers.size() if province_map else 0):
			_select_layer_item(_selected_index)
		else:
			layer_tree.deselect_all()
		_on_add_pressed()
		return
	_selected_index = item.get_metadata(0)
	_update_button_states()
	_sync_display_layer()
	_sync_polygon_edit_display()
	layer_selected.emit(_selected_index)


func _select_layer_item(index: int) -> void:
	if not layer_tree:
		return
	# Layers form a linear chain: hidden_root > layers[0] > layers[1] > ...
	var item: TreeItem = layer_tree.get_root()
	if not item:
		return
	item = item.get_first_child()
	for i: int in range(index):
		if not item:
			return
		item = item.get_first_child()
	if item:
		item.select(0)


func _sync_display_layer() -> void:
	if not display or not province_map:
		return
	if _selected_index >= 0 and _selected_index < province_map.layers.size():
		var layer: MapLayer = province_map.layers[_selected_index]
		# Show parent layer when selected layer is empty (not yet subdivided)
		if layer.regions.is_empty() and _selected_index > 0:
			display.active_layer = province_map.layers[_selected_index - 1]
		else:
			display.active_layer = layer
	else:
		display.active_layer = null


func _can_drop_image(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data is Dictionary:
		var data_dict: Dictionary = data as Dictionary
		if data_dict.has("files") and data_dict["files"] is PackedStringArray:
			var files: Array = data_dict["files"]
			if files.size() > 0:
				var ext: String = (files[0] as String).get_extension().to_lower()
				return ext in ["png", "jpg", "jpeg", "bmp", "webp", "svg"]
	return false


func _drop_image(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data is Dictionary:
		var data_dict: Dictionary = data as Dictionary
		if data_dict.has("files") and data_dict["files"] is PackedStringArray:
			var files: PackedStringArray = data_dict["files"]
			if files.size() > 0:
				_load_image(files[0] as String)


func _on_load_image_pressed() -> void:
	_file_dialog.popup_centered()


func _on_image_file_selected(path: String) -> void:
	_load_image(path)


func _load_image(path: String) -> void:
	if not province_map:
		return
	var texture: Texture2D = load(path)
	if not texture:
		return

	# Snapshot old state before initialize_from_image wipes everything.
	var old_size: Vector2 = province_map.size
	var old_vertices: Array[Vector2] = province_map.vertices.duplicate()
	var old_layers: Array[MapLayer] = province_map.layers.duplicate()

	var image: Image = texture.get_image()
	var bitmap: BitMap = BitMap.new()
	bitmap.create_from_image_alpha(image)
	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, bitmap.get_size()))
	province_map.initialize_from_image(polygons, bitmap.get_size())

	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Load Map Image")
	ur.add_do_property(province_map, "size", province_map.size)
	ur.add_do_property(province_map, "vertices", province_map.vertices.duplicate())
	ur.add_do_property(province_map, "layers", province_map.layers.duplicate())
	ur.add_undo_property(province_map, "size", old_size)
	ur.add_undo_property(province_map, "vertices", old_vertices)
	ur.add_undo_property(province_map, "layers", old_layers)
	ur.commit_action(false)

	update_display()


func _on_add_pressed() -> void:
	if not province_map or province_map.layers.is_empty():
		return
	if not subdivision_generator_scene:
		push_error("LayerEditor: subdivision_generator_scene not set")
		return
	_ensure_generator()
	var new_layer: MapLayer = MapLayer.new()
	new_layer.name = "Layer %d" % province_map.layers.size()
	_pending_new_layer = new_layer
	_generator.open(province_map, new_layer, province_map.layers.back(), editor.undo_redo)
	EditorInterface.popup_dialog_centered(_generator, Vector2i(700, 500))


func _on_generator_applied() -> void:
	# Layer insertion (for new layers) is now handled inside SubdivisionGenerator._on_apply
	# so the whole operation — subdivision + layer insertion — is one undoable action.
	if _pending_new_layer:
		_selected_index = province_map.layers.size() - 1
	_pending_new_layer = null
	update_display()
	layer_selected.emit(_selected_index)


func _on_generator_visibility_changed() -> void:
	# Generator hidden without applying — discard the pending new layer.
	if _generator and not _generator.visible:
		_pending_new_layer = null


func _on_remove_pressed() -> void:
	if not province_map or _selected_index <= 0:
		return
	var old_layers: Array[MapLayer] = province_map.layers.duplicate()
	var new_layers: Array[MapLayer] = province_map.layers.duplicate()
	new_layers.remove_at(_selected_index)
	# Update selection before committing so update_display() (fired by changed signal)
	# sees the correct index.
	_selected_index = max(0, _selected_index - 1)
	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Remove Layer")
	ur.add_do_property(province_map, "layers", new_layers)
	ur.add_undo_property(province_map, "layers", old_layers)
	ur.commit_action()


func _on_rename_pressed() -> void:
	if _selected_index < 0 or not province_map:
		return
	var layer: MapLayer = province_map.layers[_selected_index]
	_rename_line_edit.text = layer.name
	_rename_dialog.popup_centered()


func _on_rename_confirmed() -> void:
	if _selected_index < 0 or not province_map:
		return
	var new_name: String = _rename_line_edit.text.strip_edges()
	if new_name.is_empty():
		return
	var layer: MapLayer = province_map.layers[_selected_index]
	var old_name: String = layer.name
	if new_name == old_name:
		return
	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Rename Layer")
	ur.add_do_property(layer, "name", new_name)
	ur.add_undo_property(layer, "name", old_name)
	ur.commit_action()


func _ensure_generator() -> void:
	if _generator:
		return
	if not subdivision_generator_scene:
		return
	_generator = subdivision_generator_scene.instantiate()
	_generator.theme = ThemeDB.get_default_theme()
	_generator.applied.connect(_on_generator_applied)
	_generator.visibility_changed.connect(_on_generator_visibility_changed)


func _on_subdivide_pressed() -> void:
	# layers[0] cannot be a subdivision target (it has no parent)
	if not province_map or _selected_index <= 0:
		return
	if not subdivision_generator_scene:
		push_error("LayerEditor: subdivision_generator_scene not set")
		return
	_ensure_generator()
	var child_layer: MapLayer = province_map.layers[_selected_index]
	_generator.open(province_map, child_layer, null, editor.undo_redo)
	EditorInterface.popup_dialog_centered(_generator, Vector2i(700, 500))


func _update_button_states() -> void:
	var layers_size: int = province_map.layers.size() if province_map else 0
	# Can only remove the last layer (no child) and never the base layer
	var can_remove: bool = _selected_index > 0 and _selected_index == layers_size - 1
	var can_subdivide: bool = _selected_index > 0
	if add_layer_button:
		add_layer_button.disabled = layers_size == 0
	if remove_layer_button:
		remove_layer_button.disabled = not can_remove
		if can_remove:
			remove_layer_button.tooltip_text = ""
		elif _selected_index < 0:
			remove_layer_button.tooltip_text = "No layer selected."
		elif _selected_index == 0:
			remove_layer_button.tooltip_text = "The base layer cannot be removed."
		else:
			remove_layer_button.tooltip_text = "This layer has a child layer. Remove the child layer first."
	if rename_layer_button:
		rename_layer_button.disabled = _selected_index < 0
	# Can only subdivide a layer that has a parent (index > 0)
	if subdivide_button:
		subdivide_button.disabled = not can_subdivide
	if edit_layer_button:
		edit_layer_button.disabled = _selected_index < 0


func _on_edit_layer_pressed() -> void:
	if _selected_index < 0 or not province_map:
		return
	_editing_layer = !_editing_layer
	if display:
		display.visible = !_editing_layer
	if polygon_edit_display:
		polygon_edit_display.visible = _editing_layer
	_sync_polygon_edit_display()


func _sync_polygon_edit_display() -> void:
	if not polygon_edit_display or not province_map:
		return
	if _editing_layer and _selected_index >= 0 and _selected_index < province_map.layers.size():
		polygon_edit_display.province_map = province_map
		polygon_edit_display.layer = province_map.layers[_selected_index]
	else:
		polygon_edit_display.province_map = null
		polygon_edit_display.layer = null


func _refresh_polygon_display() -> void:
	_sync_polygon_edit_display()


# ---------- vertex edit handlers ----------

func _on_vertex_group_moved(global_idx: int, new_pos: Vector2) -> void:
	if not province_map or _selected_index < 0:
		return

	# Reject move if it would produce an invalid (non-triangulatable) polygon in any layer
	for layer_i: MapLayer in province_map.layers:
		for region: Region in layer_i.regions:
			for pi: int in range(region.polygon_indices.size()):
				var poly: PackedInt32Array = region.polygon_indices[pi]
				if not (global_idx in poly):
					continue
				var candidate: PackedVector2Array = PackedVector2Array()
				for idx: int in poly:
					candidate.append(new_pos if idx == global_idx else province_map.vertices[idx])
				if Geometry2D.triangulate_polygon(candidate).is_empty():
					EditorInterface.get_editor_toaster().push_toast(
						"Cannot move vertex: results in an invalid polygon",
						EditorToaster.SEVERITY_WARNING)
					return

	var old_vertices: Array[Vector2] = province_map.vertices.duplicate()
	var new_vertices: Array[Vector2] = province_map.vertices.duplicate()
	new_vertices[global_idx] = new_pos

	# Collect all regions across all layers that reference this vertex
	var affected_regions: Array[Region] = []
	for layer_i: MapLayer in province_map.layers:
		for region: Region in layer_i.regions:
			for idx_poly: PackedInt32Array in region.polygon_indices:
				if global_idx in idx_poly:
					affected_regions.append(region)
					break

	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Move Vertex")
	ur.add_do_property(province_map, "vertices", new_vertices)
	ur.add_undo_property(province_map, "vertices", old_vertices)
	for r: Region in affected_regions:
		ur.add_do_property(r, "generation_cell", PackedVector2Array())
		ur.add_undo_property(r, "generation_cell", r.generation_cell.duplicate())
	ur.add_do_method(self, "_refresh_polygon_display")
	ur.add_undo_method(self, "_refresh_polygon_display")
	ur.commit_action()


func _on_vertex_inserted(edge_a_idx: int, edge_b_idx: int, pos: Vector2) -> void:
	if not province_map or _selected_index < 0:
		return

	var old_vertices: Array[Vector2] = province_map.vertices.duplicate()
	var new_vertices: Array[Vector2] = province_map.vertices.duplicate()
	var g_new: int = new_vertices.size()
	new_vertices.append(pos)

	# Find all polygons across ALL layers with edge [A→B] or [B→A]
	var region_old_indices: Dictionary = {}
	var region_new_indices: Dictionary = {}
	var region_old_cell: Dictionary = {}
	for layer_i: MapLayer in province_map.layers:
		for region: Region in layer_i.regions:
			for pi: int in range(region.polygon_indices.size()):
				var poly: PackedInt32Array = region.polygon_indices[pi]
				var n: int = poly.size()
				for vi: int in range(n):
					var is_forward: bool = \
						poly[vi] == edge_a_idx and poly[(vi + 1) % n] == edge_b_idx
					var is_reverse: bool = \
						poly[vi] == edge_b_idx and poly[(vi + 1) % n] == edge_a_idx
					if is_forward or is_reverse:
						if not region_old_indices.has(region):
							region_old_indices[region] = \
								_copy_polygon_indices(region.polygon_indices)
							region_new_indices[region] = \
								_copy_polygon_indices(region.polygon_indices)
							region_old_cell[region] = region.generation_cell.duplicate()
						var new_poly: PackedInt32Array = PackedInt32Array()
						for k: int in range(n):
							new_poly.append(region_new_indices[region][pi][k])
							if k == vi:
								new_poly.append(g_new)
						region_new_indices[region][pi] = new_poly
						break  # only one edge per polygon can match

	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Insert Vertex")
	ur.add_do_property(province_map, "vertices", new_vertices)
	ur.add_undo_property(province_map, "vertices", old_vertices)
	for r: Region in region_old_indices:
		ur.add_do_property(r, "polygon_indices", region_new_indices[r])
		ur.add_undo_property(r, "polygon_indices", region_old_indices[r])
		ur.add_do_property(r, "generation_cell", PackedVector2Array())
		ur.add_undo_property(r, "generation_cell", region_old_cell[r])
	ur.add_do_method(self, "_refresh_polygon_display")
	ur.add_undo_method(self, "_refresh_polygon_display")
	ur.commit_action()


func _on_vertex_deleted(region: Region, poly_idx: int, vert_idx: int) -> void:
	if not province_map or _selected_index < 0:
		return

	var g: int = region.polygon_indices[poly_idx][vert_idx]

	# Remove g from every polygon across all layers that references it.
	# The display already ensures g is not shared across multiple regions in any layer
	# before emitting this signal, so this cascade is safe.
	var region_old_indices: Dictionary = {}
	var region_new_indices: Dictionary = {}
	var region_old_cell: Dictionary = {}
	for layer_i: MapLayer in province_map.layers:
		for r: Region in layer_i.regions:
			for pi: int in range(r.polygon_indices.size()):
				var poly: PackedInt32Array = r.polygon_indices[pi]
				if not (g in poly):
					continue
				if poly.size() <= 3:
					continue  # Don't drop below minimum
				if not region_old_indices.has(r):
					region_old_indices[r] = _copy_polygon_indices(r.polygon_indices)
					region_new_indices[r] = _copy_polygon_indices(r.polygon_indices)
					region_old_cell[r] = r.generation_cell.duplicate()
				var new_poly: PackedInt32Array = PackedInt32Array()
				for idx: int in region_new_indices[r][pi]:
					if idx != g:
						new_poly.append(idx)
				region_new_indices[r][pi] = new_poly

	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Delete Vertex")
	for r: Region in region_old_indices:
		ur.add_do_property(r, "polygon_indices", region_new_indices[r])
		ur.add_undo_property(r, "polygon_indices", region_old_indices[r])
		ur.add_do_property(r, "generation_cell", PackedVector2Array())
		ur.add_undo_property(r, "generation_cell", region_old_cell[r])
	ur.add_do_method(self, "_refresh_polygon_display")
	ur.add_undo_method(self, "_refresh_polygon_display")
	ur.commit_action()


# ---------- helpers ----------

func _copy_polygon_indices(src: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for poly: PackedInt32Array in src:
		result.append(PackedInt32Array(poly))
	return result
