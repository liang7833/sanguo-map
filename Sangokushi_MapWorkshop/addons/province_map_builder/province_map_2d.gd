@tool
class_name ProvinceMap2D extends Node2D

## Runtime node for displaying and interacting with a ProvinceMap resource.
##
## Drop into a scene, assign a ProvinceMap, pick a render_source from the dropdown,
## then connect signals to react to hover/click.
##
## Coordinate space: polygons are drawn in this node's local space using their raw map
## coordinates. Scale or transform the node to fit your scene.
##
## Example — hit-testing from an _input handler:
##   var region = map.get_region_at_position(to_local(get_global_mouse_position()))
##
## Example — mutating data and refreshing:
##   map.set_property(region, "owner", my_country)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the mouse enters a new region.
signal region_hovered(region: Region, layer: MapLayer)

## Emitted when the mouse leaves the previously hovered region.
signal region_unhovered(region: Region, layer: MapLayer)

## Emitted on mouse button press over a region.
signal region_pressed(region: Region, layer: MapLayer, button: MouseButton)

## Emitted on mouse button release over a region.
signal region_released(region: Region, layer: MapLayer, button: MouseButton)

## Emitted when the mouse is pressed and released over the same region (full click).
signal region_clicked(region: Region, layer: MapLayer, button: MouseButton)


# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## The map resource to render. Assigning a new map refreshes the render_source dropdown.
@export var province_map: ProvinceMap:
	set(value):
		if province_map and province_map.changed.is_connected(_on_province_map_changed):
			province_map.changed.disconnect(_on_province_map_changed)
		province_map = value
		if province_map:
			province_map.changed.connect(_on_province_map_changed)
		notify_property_list_changed()
		update_configuration_warnings()
		queue_redraw()

## Selects which layer to render and interact with, and how its regions are coloured.
## Format: "LayerName/RenderModeLabel" — choose from the dropdown in the inspector.
## Layers without a schema or with no render modes appear as just "LayerName" and
## fall back to region.color. Falls back to the first layer when empty or not found.
@export var render_source: String:
	set(value):
		render_source = value
		update_configuration_warnings()
		queue_redraw()

## When false, hover/click signals are suppressed and hover state is cleared.
## Useful when your game handles input in another state (e.g. UI open, cutscene).
@export var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not input_enabled:
			_clear_hover()

## Draw borders between adjacent regions that share the same rendered property value
## (e.g. province boundaries within a single country).
@export var show_borders: bool = false:
	set(value):
		show_borders = value
		queue_redraw()

@export var border_color: Color = Color.BLACK:
	set(value):
		border_color = value
		queue_redraw()

@export var border_width: float = 1.0:
	set(value):
		border_width = value
		queue_redraw()

## Draw borders between adjacent regions that have different rendered property values
## (e.g. the border between two countries).
@export var show_outer_border: bool = true:
	set(value):
		show_outer_border = value
		queue_redraw()

@export var outer_border_color: Color = Color.BLACK:
	set(value):
		outer_border_color = value
		queue_redraw()

@export var outer_border_width: float = 2.0:
	set(value):
		outer_border_width = value
		queue_redraw()


# ---------------------------------------------------------------------------
# Runtime-settable (not exported)
# ---------------------------------------------------------------------------

## Called with (region_a: Region, region_b: Region) -> bool before drawing each shared edge.
## Return false to skip drawing that border. null = draw all borders.
## Example: func(a, b): return a.data.country != b.data.country
var border_condition: Callable

## Called with (region: Region) -> bool to mark regions impassable for pathfinding.
## Return false to disable the region. null = all regions passable.
var passability_condition: Callable


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _hovered_region: Region = null
var _pressed_region: Region = null
var _pressed_button: MouseButton = MOUSE_BUTTON_NONE

## Adjacency cache: MapLayer -> {shared_edges: PackedInt32Array, outer_edges: PackedInt32Array,
##                                neighbors: Array[Array[int]]}
var _adj_cache: Dictionary = {}

## AStar2D cache per layer. Invalidated when province_map.changed fires or rebuild_pathfinding
## is called.
var _astar_cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if province_map and not province_map.changed.is_connected(_on_province_map_changed):
		province_map.changed.connect(_on_province_map_changed)


func _on_province_map_changed() -> void:
	_invalidate_caches()
	notify_property_list_changed()
	update_configuration_warnings()
	queue_redraw()


# ---------------------------------------------------------------------------
# Editor validation
# ---------------------------------------------------------------------------

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not province_map:
		warnings.append("No ProvinceMap assigned.")
		return warnings
	if province_map.layers.is_empty():
		warnings.append("ProvinceMap has no layers.")
		return warnings
	if not render_source.is_empty():
		var layer_name: String = render_source.split("/")[0]
		var found: bool = false
		for layer: MapLayer in province_map.layers:
			if layer.name == layer_name:
				found = true
				break
		if not found:
			warnings.append(
				"render_source: layer '%s' not found in the assigned ProvinceMap." % layer_name)
	return warnings


## Populates the render_source inspector field with a dropdown of all available
## layer/render-mode combinations from the assigned province_map.
func _validate_property(property: Dictionary) -> void:
	if property.name != "render_source":
		return
	if not province_map or province_map.layers.is_empty():
		return
	var entries: PackedStringArray = PackedStringArray()
	for layer: MapLayer in province_map.layers:
		var modes: Array[RenderMode] = _get_schema_render_modes(layer)
		if modes.is_empty():
			entries.append(layer.name)
		else:
			for mode: RenderMode in modes:
				entries.append(layer.name + "/" + mode.label)
	if not entries.is_empty():
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(entries)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not province_map:
		return
	var layer: MapLayer = _resolve_layer()
	if not layer or layer.regions.is_empty():
		return
	var mode: RenderMode = _resolve_render_mode(layer)
	for region: Region in layer.regions:
		var color: Color = region.color
		if mode and region.data:
			color = mode.evaluate.call(region.data)
		for polygon: PackedVector2Array in province_map.get_resolved_polygons(region):
			if polygon.size() < 3:
				continue
			draw_colored_polygon(polygon, color)

	if show_borders or show_outer_border:
		var adj_data: Dictionary = _get_adj_data(layer)
		var shared: PackedInt32Array = adj_data["shared_edges"]
		var inner_pts: PackedVector2Array = PackedVector2Array()
		var outer_pts: PackedVector2Array = PackedVector2Array()

		for i: int in range(0, shared.size(), 4):
			var ra: int = shared[i + 2]
			var rb: int = shared[i + 3]
			var region_a: Region = layer.regions[ra]
			var region_b: Region = layer.regions[rb]

			if border_condition.is_valid() and not border_condition.call(region_a, region_b):
				continue

			var pt_a: Vector2 = province_map.vertices[shared[i]]
			var pt_b: Vector2 = province_map.vertices[shared[i + 1]]
			if _get_render_value(region_a, mode) == _get_render_value(region_b, mode):
				inner_pts.append(pt_a)
				inner_pts.append(pt_b)
			else:
				outer_pts.append(pt_a)
				outer_pts.append(pt_b)

		if show_outer_border:
			var coastline: PackedInt32Array = adj_data["outer_edges"]
			for i: int in range(0, coastline.size(), 2):
				outer_pts.append(province_map.vertices[coastline[i]])
				outer_pts.append(province_map.vertices[coastline[i + 1]])

		if show_borders and not inner_pts.is_empty():
			draw_multiline(inner_pts, border_color, border_width)
		if show_outer_border and not outer_pts.is_empty():
			draw_multiline(outer_pts, outer_border_color, outer_border_width)


## Redraws the map. Call after externally mutating region data.
func force_redraw() -> void:
	queue_redraw()


# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

## Returns the MapLayer at index, or null if index is out of range.
func get_layer(index: int) -> MapLayer:
	if not province_map or index < 0 or index >= province_map.layers.size():
		return null
	return province_map.layers[index]


## Returns the first MapLayer whose name matches, or null if not found.
func get_layer_by_name(layer_name: String) -> MapLayer:
	if not province_map:
		return null
	for layer: MapLayer in province_map.layers:
		if layer.name == layer_name:
			return layer
	return null


## Returns the Region under local_pos in the active source layer, or null if none.
## local_pos is in this node's local coordinate space.
## Typical usage: get_region_at_position(to_local(get_global_mouse_position()))
func get_region_at_position(local_pos: Vector2) -> Region:
	if not province_map:
		return null
	var layer: MapLayer = _resolve_layer()
	if not layer:
		return null
	for region: Region in layer.regions:
		for polygon: PackedVector2Array in province_map.get_resolved_polygons(region):
			if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(local_pos, polygon):
				return region
	return null


# ---------------------------------------------------------------------------
# Property mutation API
# ---------------------------------------------------------------------------

## Sets a named property on region.data and triggers a redraw.
## property must exactly match a GDScript variable name on the layer's RegionDataSchema subclass.
func set_property(region: Region, property: String, value: Variant) -> void:
	if not region or not region.data:
		push_warning("ProvinceMap2D.set_property: region has no data — is a schema assigned to the layer?")
		return
	region.data.set(property, value)
	queue_redraw()


## Returns the value of a named property from region.data.
## Returns null if region is null, has no data, or the property does not exist.
func get_property(region: Region, property: String) -> Variant:
	if not region or not region.data:
		return null
	return region.data.get(property)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not input_enabled or not province_map:
		return

	if event is InputEventMouseMotion:
		var local_pos: Vector2 = to_local(get_global_mouse_position())
		var region: Region = get_region_at_position(local_pos)
		var layer: MapLayer = _resolve_layer()
		if region != _hovered_region:
			if _hovered_region and layer:
				region_unhovered.emit(_hovered_region, layer)
			_hovered_region = region
			if _hovered_region and layer:
				region_hovered.emit(_hovered_region, layer)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var local_pos: Vector2 = to_local(get_global_mouse_position())
		var region: Region = get_region_at_position(local_pos)
		var layer: MapLayer = _resolve_layer()
		if mb.pressed:
			if region and layer:
				_pressed_region = region
				_pressed_button = mb.button_index
				region_pressed.emit(region, layer, mb.button_index)
		else:
			if region and layer:
				region_released.emit(region, layer, mb.button_index)
				if region == _pressed_region and mb.button_index == _pressed_button:
					region_clicked.emit(region, layer, mb.button_index)
			_pressed_region = null
			_pressed_button = MOUSE_BUTTON_NONE


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _resolve_layer() -> MapLayer:
	if not province_map or province_map.layers.is_empty():
		return null
	if render_source.is_empty():
		return province_map.layers[0]
	var layer_name: String = render_source.split("/")[0]
	for layer: MapLayer in province_map.layers:
		if layer.name == layer_name:
			return layer
	return province_map.layers[0]


func _resolve_render_mode(layer: MapLayer) -> RenderMode:
	if render_source.is_empty() or not "/" in render_source:
		return null
	var mode_label: String = render_source.split("/", true, 1)[1]
	for mode: RenderMode in _get_schema_render_modes(layer):
		if mode.label == mode_label:
			return mode
	return null


func _get_render_value(region: Region, mode: RenderMode) -> Color:
	if mode and region.data:
		return mode.evaluate.call(region.data)
	return region.color


func _get_schema_render_modes(layer: MapLayer) -> Array[RenderMode]:
	if not layer.data_schema:
		return []
	var instance: RegionDataSchema = layer.data_schema.new() as RegionDataSchema
	if not instance:
		return []
	return instance.get_render_modes()


# ---------------------------------------------------------------------------
# Pathfinding API
# ---------------------------------------------------------------------------

## Returns the shortest path from `from` to `to` as an Array[Region].
## Uses the active render layer unless `layer` is supplied.
## Returns an empty array if either region is not found in the layer, or no path exists.
func find_path(from: Region, to: Region, layer: MapLayer = null) -> Array[Region]:
	var target_layer: MapLayer = layer if layer else _resolve_layer()
	if not target_layer:
		return []
	var from_idx: int = target_layer.regions.find(from)
	var to_idx: int = target_layer.regions.find(to)
	if from_idx == -1 or to_idx == -1:
		return []
	var astar: AStar2D = _get_astar(target_layer)
	var id_path: PackedInt64Array = astar.get_id_path(from_idx, to_idx)
	var result: Array[Region] = []
	for id: int in id_path:
		result.append(target_layer.regions[id])
	return result


## Returns all regions adjacent to `region` in the active layer (or the supplied layer).
func get_neighbors(region: Region, layer: MapLayer = null) -> Array[Region]:
	var target_layer: MapLayer = layer if layer else _resolve_layer()
	if not target_layer:
		return []
	var ri: int = target_layer.regions.find(region)
	if ri == -1:
		return []
	var adj_data: Dictionary = _get_adj_data(target_layer)
	var neighbors: Array = adj_data["neighbors"]
	var result: Array[Region] = []
	for idx: int in neighbors[ri]:
		result.append(target_layer.regions[idx])
	return result


## Clears the AStar cache so it is rebuilt on next use.
## Call after changing passability_condition at runtime.
func rebuild_pathfinding() -> void:
	_astar_cache.clear()


# ---------------------------------------------------------------------------
# Internal helpers — adjacency & pathfinding
# ---------------------------------------------------------------------------

## Builds and caches adjacency data for a layer.
## Returns a Dictionary with keys:
##   shared_edges: PackedInt32Array  — flat layout [va, vb, ra, rb, ...]
##   outer_edges:  PackedInt32Array  — flat layout [va, vb, ...]
##   neighbors:    Array             — neighbors[i] = Array[int] of adjacent region indices
func _get_adj_data(layer: MapLayer) -> Dictionary:
	if _adj_cache.has(layer):
		return _adj_cache[layer]

	# edge_map: key -> [va, vb, ri_first] or [va, vb, ri_first, ri_second]
	var edge_map: Dictionary = {}
	for ri: int in range(layer.regions.size()):
		var region: Region = layer.regions[ri]
		for idx_poly: PackedInt32Array in region.polygon_indices:
			var n: int = idx_poly.size()
			for i: int in range(n):
				var va: int = idx_poly[i]
				var vb: int = idx_poly[(i + 1) % n]
				var key: String = "%d_%d" % [min(va, vb), max(va, vb)]
				if edge_map.has(key):
					var entry: Array = edge_map[key]
					if entry.size() == 3 and entry[2] != ri:
						entry.append(ri)
						edge_map[key] = entry
				else:
					edge_map[key] = [va, vb, ri]

	var shared_edges: PackedInt32Array = PackedInt32Array()
	var outer_edges: PackedInt32Array = PackedInt32Array()
	var neighbor_sets: Array = []
	for _i: int in range(layer.regions.size()):
		neighbor_sets.append({})

	for key: String in edge_map:
		var entry: Array = edge_map[key]
		if entry.size() == 4:
			var va: int = entry[0]
			var vb: int = entry[1]
			var ra: int = entry[2]
			var rb: int = entry[3]
			shared_edges.append(va)
			shared_edges.append(vb)
			shared_edges.append(ra)
			shared_edges.append(rb)
			neighbor_sets[ra][rb] = true
			neighbor_sets[rb][ra] = true
		elif entry.size() == 3:
			outer_edges.append(entry[0])
			outer_edges.append(entry[1])

	var neighbors: Array = []
	for i: int in range(layer.regions.size()):
		var ns: Array[int] = []
		for idx: Variant in neighbor_sets[i]:
			ns.append(idx as int)
		neighbors.append(ns)

	var data: Dictionary = {
		"shared_edges": shared_edges,
		"outer_edges": outer_edges,
		"neighbors": neighbors,
	}
	_adj_cache[layer] = data
	return data


## Builds and caches an AStar2D for a layer using region centers as node positions.
func _get_astar(layer: MapLayer) -> AStar2D:
	if _astar_cache.has(layer):
		return _astar_cache[layer]

	var adj_data: Dictionary = _get_adj_data(layer)
	var astar: AStar2D = AStar2D.new()

	for i: int in range(layer.regions.size()):
		var region: Region = layer.regions[i]
		astar.add_point(i, region.center)
		if passability_condition.is_valid() and not passability_condition.call(region):
			astar.set_point_disabled(i, true)

	var shared: PackedInt32Array = adj_data["shared_edges"]
	for i: int in range(0, shared.size(), 4):
		var ra: int = shared[i + 2]
		var rb: int = shared[i + 3]
		if not astar.are_points_connected(ra, rb):
			astar.connect_points(ra, rb, true)

	_astar_cache[layer] = astar
	return astar


func _invalidate_caches() -> void:
	_adj_cache.clear()
	_astar_cache.clear()


func _clear_hover() -> void:
	if _hovered_region:
		var layer: MapLayer = _resolve_layer()
		if layer:
			region_unhovered.emit(_hovered_region, layer)
		_hovered_region = null
