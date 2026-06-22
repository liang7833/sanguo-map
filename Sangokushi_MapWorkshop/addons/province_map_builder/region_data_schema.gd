@tool
@abstract class_name RegionDataSchema extends Resource

# Base class for user-defined per-layer data schemas.
#
# Usage: extend this class and add @export properties for your layer's fields.
# Then override get_render_modes() to control how regions are coloured in the
# metadata editor and at runtime in ProvinceMap2D.
#
#   class_name ProvinceSchema extends RegionDataSchema
#   enum Terrain { PLAINS, FOREST, MOUNTAIN, COAST }
#   @export var country: Country = null
#   @export var terrain: Terrain = Terrain.PLAINS
#   @export var population: int = 0
#
#   func get_render_modes() -> Array[RenderMode]:
#       return [
#           RenderMode.new("By Country", "country",
#               func(d: ProvinceSchema): return d.country.color if d.country else Color.GRAY),
#           RenderMode.new("By Terrain", "terrain",
#               func(d: ProvinceSchema): return TERRAIN_COLORS.get(d.terrain, Color.WHITE)),
#       ]
#
# Assign the script (not an instance) to MapLayer.data_schema in the editor.
# The plugin creates instances automatically for each region.


# Returns a list of RenderModes for this schema.
# Each mode maps region data to a Color for one visual representation.
# Override in your subclass to control paint preview colours in the metadata editor
# and rendering in ProvinceMap2D. Returning [] causes the metadata editor to fall back
# to generic hash colours and show a warning icon on unmatched properties.
func get_render_modes() -> Array[RenderMode]:
	return []


# Returns a fresh instance of this schema with all properties at their defaults.
# Override in your subclass if you need custom default initialisation.
func make_default_data() -> RegionDataSchema:
	return get_script().new()


# Creates a fresh instance and copies compatible properties from old_data.
# Compatible = same property name AND same Variant.Type.
# Override in your subclass for custom migration (e.g. renamed properties).
func migrate_data(old_data: Resource) -> RegionDataSchema:
	var new_instance: RegionDataSchema = get_script().new()
	if not old_data:
		return new_instance

	# Build lookup of old property names → Variant.Type
	var old_props: Dictionary = {}
	for prop: Dictionary in old_data.get_property_list():
		old_props[prop.name] = prop.type

	for prop: Dictionary in new_instance.get_property_list():
		# Only copy user-defined script properties, not built-in Resource fields
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname: String = prop.name
		if pname not in old_props:
			continue
		if old_props[pname] != prop.type:
			continue
		new_instance.set(pname, old_data.get(pname))

	return new_instance
