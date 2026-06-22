class_name RenderMode extends RefCounted

## A named colour-mapping rule defined inside a RegionDataSchema subclass.
##
## Usage — in your schema's get_render_modes():
##   return [
##       RenderMode.new("By Country", "country",
##           func(d: MySchema): return d.country.color if d.country else Color.GRAY),
##   ]


## Human-readable name. Shown in editor dropdowns and used as the key in ProvinceMap2D exports.
var label: String

## The schema property this mode primarily visualises.
##
## Must exactly match the property name as returned by get_property_list() on the schema
## (i.e. the GDScript variable name, e.g. "country", "terrain", "population").
##
## The metadata editor uses this to auto-match a mode to the active property dropdown:
## when the user selects property "country", the first RenderMode with property == "country"
## is used for the paint preview instead of the generic hash fallback.
##
## Leave empty ("") if the mode is not tied to a single property (e.g. a composite mode).
## Empty-property modes are never auto-matched by the metadata editor.
var property: String

## Callable with signature: func(data: RegionDataSchema) -> Color.
## Called once per region during preview and runtime rendering.
## [param data] is guaranteed non-null when called.
var evaluate: Callable


func _init(p_label: String, p_property: String, p_evaluate: Callable) -> void:
	label = p_label
	property = p_property
	evaluate = p_evaluate
