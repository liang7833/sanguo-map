@tool
class_name MetadataEditor extends BaseSubEditor

# Expected exports (wire in scene):
#   layer_option: OptionButton        — layer selector, always visible
#   schema_picker_container: Control  — EditorResourcePicker created here, always visible
#   paint_button: Button              — toggle_mode=true, in a ButtonGroup with inspect_button
#   inspect_button: Button            — toggle_mode=true, in the same ButtonGroup
#   paint_mode_container: Control     — visible only in paint mode
#     paint_property_option: OptionButton — property selector (inside paint_mode_container)
#     render_mode_warning: TextureRect    — small icon shown when no render mode covers the property
#     paint_value_container: Control      — dynamic value widget added here (inside paint_mode_container)
#   inspect_mode_container: Control   — visible only in inspect mode, EditorInspector added here
#   display: ProvinceMapDisplay       — right panel, always visible
#
# Button setup in scene: both buttons need toggle_mode=true and the same ButtonGroup assigned.
# paint_button should have button_pressed=true (default mode).
# render_mode_warning: add a TextureRect node near the property dropdown; leave texture unset
#   (set in code). Stretch Mode = Keep Aspect Centered, size ~16x16.

@export var layer_option: OptionButton
@export var schema_picker_container: Control
@export var paint_button: Button
@export var inspect_button: Button
@export var paint_mode_container: Control
@export var paint_property_option: OptionButton
@export var render_mode_warning: TextureRect
@export var paint_value_container: Control
@export var painting_container: Control # hide this when no property selected
@export var inspect_mode_container: Control
@export var display: ProvinceMapDisplay

var _active_layer: MapLayer = null
var _schema_props: Array = []
var _render_modes: Array[RenderMode] = []
var _paint_control: Control = null
var _schema_picker: EditorResourcePicker = null
var _inspector: EditorInspector = null
var _selected_region: Region = null
var _selected_region_index: int = -1
var _blink_time: float = 0.0
var _is_paint_mode: bool = true
var _is_painting: bool = false

var _on_layer_selected_cb: Callable
var _on_property_selected_cb: Callable
var _on_display_input_cb: Callable
var _on_schema_changed_cb: Callable
var _on_paint_pressed_cb: Callable
var _on_inspect_pressed_cb: Callable
var _on_version_changed_cb: Callable


func _enter_tree() -> void:
	super._enter_tree()
	_on_layer_selected_cb = _on_layer_selected
	_on_property_selected_cb = _on_property_selected
	_on_display_input_cb = _on_display_input
	_on_schema_changed_cb = _on_schema_changed
	_on_paint_pressed_cb = func(): _set_mode(true)
	_on_inspect_pressed_cb = func(): _set_mode(false)
	_on_version_changed_cb = _recompute_color_overrides

	if layer_option:
		layer_option.item_selected.connect(_on_layer_selected_cb)
	if paint_property_option:
		paint_property_option.item_selected.connect(_on_property_selected_cb)
	if display:
		display.gui_input.connect(_on_display_input_cb)
	if paint_button:
		paint_button.icon = get_theme_icon("CanvasItem", "EditorIcons")
		paint_button.pressed.connect(_on_paint_pressed_cb)
	if inspect_button:
		inspect_button.icon = get_theme_icon("Search", "EditorIcons")
		inspect_button.pressed.connect(_on_inspect_pressed_cb)
	if render_mode_warning:
		render_mode_warning.texture = get_theme_icon("StatusWarning", "EditorIcons")
		render_mode_warning.visible = false
	if editor and editor.undo_redo:
		editor.undo_redo.version_changed.connect(_on_version_changed_cb)

	_build_schema_picker()
	_set_mode(true)


func _exit_tree() -> void:
	super._exit_tree()
	if layer_option:
		layer_option.item_selected.disconnect(_on_layer_selected_cb)
	if paint_property_option:
		paint_property_option.item_selected.disconnect(_on_property_selected_cb)
	if display:
		display.gui_input.disconnect(_on_display_input_cb)
	if paint_button and _on_paint_pressed_cb.is_valid():
		paint_button.pressed.disconnect(_on_paint_pressed_cb)
	if inspect_button and _on_inspect_pressed_cb.is_valid():
		inspect_button.pressed.disconnect(_on_inspect_pressed_cb)
	if editor and editor.undo_redo and editor.undo_redo.version_changed.is_connected(_on_version_changed_cb):
		editor.undo_redo.version_changed.disconnect(_on_version_changed_cb)
	if _schema_picker:
		_schema_picker.resource_changed.disconnect(_on_schema_changed_cb)
		_schema_picker.queue_free()
		_schema_picker = null


# --- Setup ---

func _build_schema_picker() -> void:
	if not schema_picker_container:
		return
	_schema_picker = EditorResourcePicker.new()
	_schema_picker.base_type = "Script"
	_schema_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_schema_picker.custom_minimum_size = Vector2(120, 0)
	_schema_picker.resource_changed.connect(_on_schema_changed_cb)
	schema_picker_container.add_child(_schema_picker)


# --- BaseSubEditor override ---

func update_display() -> void:
	if not province_map or not layer_option:
		return
	var prev_idx: int = maxi(layer_option.selected, 0)
	layer_option.clear()
	for layer: MapLayer in province_map.layers:
		layer_option.add_item(layer.name)
	var new_idx: int = clampi(prev_idx, 0, province_map.layers.size() - 1)
	layer_option.selected = new_idx
	_set_active_layer_index(new_idx)


# --- Layer & schema ---

func _on_layer_selected(index: int) -> void:
	_set_active_layer_index(index)


func _set_active_layer_index(index: int) -> void:
	if not province_map or province_map.layers.is_empty():
		_active_layer = null
		_sync_schema_picker()
		_refresh_schema_ui()
		return
	_active_layer = province_map.layers[index]
	if display:
		display.province_map = province_map
		display.active_layer = _active_layer
		display.region_color_overrides = {}
		display.highlighted_region = null
	_selected_region = null
	_selected_region_index = -1
	_blink_time = 0.0
	if _inspector:
		_inspector.edit(null)
	_sync_schema_picker()
	_refresh_schema_ui()


func _sync_schema_picker() -> void:
	if not _schema_picker:
		return
	if _active_layer:
		_schema_picker.edited_resource = _active_layer.data_schema
		_schema_picker.editable = true
	else:
		_schema_picker.edited_resource = null
		_schema_picker.editable = false


func _on_schema_changed(script: Resource) -> void:
	if not _active_layer:
		return
	if script != null and not _is_valid_schema(script as Script):
		EditorInterface.get_editor_toaster().push_toast(
			"Schema must extend RegionDataSchema", EditorToaster.SEVERITY_WARNING)
		_schema_picker.edited_resource = _active_layer.data_schema
		return
	var old_schema: Script = _active_layer.data_schema
	var new_schema: Script = script as Script
	if new_schema == old_schema:
		return
	var ur: EditorUndoRedoManager = editor.undo_redo
	ur.create_action("Set Layer Schema")
	ur.add_do_property(_active_layer, "data_schema", new_schema)
	ur.add_undo_property(_active_layer, "data_schema", old_schema)
	ur.commit_action()
	# _refresh_schema_ui() is called automatically via MapLayer.changed →
	# province_map.changed → update_display() → _set_active_layer_index() → _refresh_schema_ui()


func _is_valid_schema(script: Script) -> bool:
	if script == null:
		return true
	var instance: Object = script.new()
	var valid: bool = instance is RegionDataSchema
	if instance is RefCounted:
		pass  # freed automatically
	else:
		instance.free()
	return valid


# --- Schema UI ---

func _refresh_schema_ui() -> void:
	_schema_props = []
	_render_modes = []
	if paint_property_option:
		paint_property_option.clear()

	if _active_layer and _active_layer.data_schema:
		var temp: RegionDataSchema = _active_layer.data_schema.new()
		for prop: Dictionary in temp.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			_schema_props.append(prop)
			if paint_property_option:
				paint_property_option.add_item(prop.name)
		_render_modes = temp.get_render_modes()
		if _schema_props.is_empty() and paint_property_option:
			paint_property_option.add_item("No property selected")
			paint_property_option.set_item_disabled(0, true)
	elif paint_property_option:
		paint_property_option.add_item("No schema defined")
		paint_property_option.set_item_disabled(0, true)

	if painting_container:
		painting_container.visible = not _schema_props.is_empty()

	_build_paint_value_editor()
	_recompute_color_overrides()


func _on_property_selected(_index: int) -> void:
	_build_paint_value_editor()
	_update_render_mode_warning()
	_recompute_color_overrides()


func _build_paint_value_editor() -> void:
	if _paint_control:
		_paint_control.queue_free()
		_paint_control = null

	if _schema_props.is_empty() or not paint_property_option \
			or paint_property_option.selected < 0 or not paint_value_container:
		return

	var prop: Dictionary = _schema_props[paint_property_option.selected]

	match prop.type:
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				var btn: OptionButton = OptionButton.new()
				for entry: String in prop.hint_string.split(","):
					btn.add_item(entry.split(":")[0])
				btn.item_selected.connect(func(_i: int): _recompute_color_overrides())
				_paint_control = btn
			else:
				var spin: SpinBox = SpinBox.new()
				spin.min_value = -999999
				spin.max_value = 999999
				spin.step = 1
				spin.value_changed.connect(func(_v: float): _recompute_color_overrides())
				_paint_control = spin
		TYPE_FLOAT:
			var spin: SpinBox = SpinBox.new()
			spin.min_value = -999999.0
			spin.max_value = 999999.0
			spin.step = 0.01
			spin.value_changed.connect(func(_v: float): _recompute_color_overrides())
			_paint_control = spin
		TYPE_STRING:
			var edit: LineEdit = LineEdit.new()
			edit.text_changed.connect(func(_t: String): _recompute_color_overrides())
			_paint_control = edit
		TYPE_BOOL:
			var check: CheckBox = CheckBox.new()
			check.toggled.connect(func(_b: bool): _recompute_color_overrides())
			_paint_control = check
		TYPE_COLOR:
			var picker: ColorPickerButton = ColorPickerButton.new()
			picker.color_changed.connect(func(_c: Color): _recompute_color_overrides())
			_paint_control = picker
		TYPE_OBJECT:
			var picker: EditorResourcePicker = EditorResourcePicker.new()
			picker.base_type = prop.class_name
			picker.custom_minimum_size = Vector2(120, 0)
			picker.resource_changed.connect(func(_r: Resource): _recompute_color_overrides())
			_paint_control = picker

	if _paint_control:
		_paint_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		paint_value_container.add_child(_paint_control)


func _get_paint_value() -> Variant:
	if not _paint_control or _schema_props.is_empty() \
			or not paint_property_option or paint_property_option.selected < 0:
		return null
	var prop: Dictionary = _schema_props[paint_property_option.selected]
	match prop.type:
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				return (_paint_control as OptionButton).selected
			return int((_paint_control as SpinBox).value)
		TYPE_FLOAT:
			return (_paint_control as SpinBox).value
		TYPE_STRING:
			return (_paint_control as LineEdit).text
		TYPE_BOOL:
			return (_paint_control as CheckBox).button_pressed
		TYPE_COLOR:
			return (_paint_control as ColorPickerButton).color
		TYPE_OBJECT:
			return (_paint_control as EditorResourcePicker).edited_resource
	return null


# --- Mode ---

func _set_mode(paint: bool) -> void:
	_is_paint_mode = paint
	_is_painting = false

	if paint_mode_container:
		paint_mode_container.visible = paint
	if inspect_mode_container:
		inspect_mode_container.visible = not paint

	if paint:
		_selected_region = null
		_selected_region_index = -1
		_blink_time = 0.0
		_recompute_color_overrides()
	else:
		if display:
			display.region_color_overrides = {}


# --- Display input ---

func _on_display_input(event: InputEvent) -> void:
	if not _active_layer or not display:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_painting = mb.pressed and _is_paint_mode
			if mb.pressed:
				_handle_click(mb.position)
	elif event is InputEventMouseMotion and _is_painting:
		_handle_click((event as InputEventMouseMotion).position)


func _handle_click(pos: Vector2) -> void:
	var region_idx: int = display.get_region_at_position(pos, _active_layer)
	if region_idx < 0:
		return
	var region: Region = _active_layer.regions[region_idx]
	if _is_paint_mode:
		_paint_region(region)
	else:
		_inspect_region(region)


# --- Paint ---

func _paint_region(region: Region) -> void:
	if not region.data or _schema_props.is_empty() \
			or not paint_property_option or paint_property_option.selected < 0:
		return
	var prop_name: String = _schema_props[paint_property_option.selected].name
	var new_value: Variant = _get_paint_value()
	var old_value: Variant = region.data.get(prop_name)
	if new_value == old_value:
		return

	editor.undo_redo.create_action("Paint Region Property")
	editor.undo_redo.add_do_property(region.data, prop_name, new_value)
	editor.undo_redo.add_undo_property(region.data, prop_name, old_value)
	editor.undo_redo.commit_action()

	_recompute_color_overrides()


# --- Inspect ---

func _inspect_region(region: Region) -> void:
	_selected_region = region
	_selected_region_index = _active_layer.regions.find(region)
	_blink_time = 0.0

	if not inspect_mode_container:
		return
	if not _inspector:
		_inspector = EditorInspector.new()
		_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inspect_mode_container.add_child(_inspector)
	_inspector.edit(region.data)


func _process(delta: float) -> void:
	if _is_paint_mode or not _selected_region or not display or _selected_region_index < 0:
		return
	_blink_time += delta
	var t: float = 0.5 + 0.5 * sin(_blink_time * TAU / 1.5)
	var base: Color = _selected_region.color
	var v: float = lerpf(base.v * 0.8, minf(base.v * 1.2, 1.0), t)
	display.region_color_overrides = {
		_selected_region_index: Color.from_hsv(base.h, base.s, v, base.a)
	}


# --- Color overrides ---

func _recompute_color_overrides() -> void:
	if not display or not _active_layer:
		return
	var overrides: Dictionary = {}
	if not _schema_props.is_empty() and paint_property_option \
			and paint_property_option.selected >= 0:
		var prop_name: String = _schema_props[paint_property_option.selected].name
		for i: int in range(_active_layer.regions.size()):
			var region: Region = _active_layer.regions[i]
			if region.data:
				overrides[i] = _get_region_color(region, prop_name)
	display.region_color_overrides = overrides
	_update_render_mode_warning()


func _get_region_color(region: Region, prop_name: String) -> Color:
	# Tier 1: use schema-defined render mode for this property
	var mode: RenderMode = _find_render_mode_for_property(prop_name)
	if mode:
		return mode.evaluate.call(region.data)
	# Tier 2: generic fallback (dev aid only)
	return _hash_color(region.data.get(prop_name))


func _find_render_mode_for_property(prop_name: String) -> RenderMode:
	for mode: RenderMode in _render_modes:
		if mode.property == prop_name:
			return mode
	return null


func _update_render_mode_warning() -> void:
	if not render_mode_warning:
		return
	if _schema_props.is_empty() or not paint_property_option \
			or paint_property_option.selected < 0:
		render_mode_warning.visible = false
		return
	var prop_name: String = _schema_props[paint_property_option.selected].name
	var has_mode: bool = _find_render_mode_for_property(prop_name) != null
	render_mode_warning.visible = not has_mode
	if not has_mode:
		render_mode_warning.tooltip_text = \
			"No render mode defined for '%s' — using fallback colours.\nOverride get_render_modes() in your schema to control this." \
			% prop_name


func _hash_color(val: Variant) -> Color:
	if val == null:
		return Color(0.5, 0.5, 0.5, 0.4)
	if val is Color:
		return val
	var h: float = fmod(abs(float(hash(val))) * 0.618033988749895, 1.0)
	return Color.from_hsv(h, 0.65, 0.85)
