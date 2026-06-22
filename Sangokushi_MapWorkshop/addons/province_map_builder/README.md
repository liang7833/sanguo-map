# Province Map Builder

A Godot 4.6 editor plugin for building province maps for grand strategy games. Define a map shape from an image, divide it into region layers, define metadata for each region, and render an interactive map at runtime.

## Features

- **Map outline import** — select an image in the Layers tab to extract the landmass outline as an editable polygon
- **Divide-down layer hierarchy** — define as many layers as you need (e.g. Continents → Countries → Provinces), each layer subdivides the one above it
- **Voronoi auto-subdivision** — generate child regions automatically using Voronoi cells, with Lloyd relaxation for more natural-looking results
- **Typed region data** — write a GDScript class to define per-region properties (strings, numbers, booleans, colors); the editor generates a typed form for each region
- **Paint & inspect modes** — click regions on the map to paint property values or inspect and edit all fields at once
- **Runtime node (`ProvinceMap2D`)** — add to any scene to render the map, receive hover/click signals, query and mutate region data, and run pathfinding between regions

![Inspect mode](images/inspect-mode.png)

## Requirements

- Godot **4.6+**

## Installation

### **Asset Library** (recommended)

Search for **Province Map Builder** in the Godot Asset Library, or open the plugin page directly:
https://godotengine.org/asset-library/asset/4973

Then enable the plugin in the engine: **Project → Project Settings → Plugins** → enable *Province Map Builder*

### **Manual**

1. Download the latest release zip from the [releases page](https://gitlab.com/OskarUnn/province-map-builder/-/releases)
2. Copy the `addons/province_map_builder/` folder into your project's `addons/` directory

Then enable the plugin in the engine: **Project → Project Settings → Plugins** → enable *Province Map Builder*

## Quick Start

1. Add a `ProvinceMap2D` node to your scene and create a new `ProvinceMap` resource on it in the Inspector — the **Province Map** dock opens at the bottom of the editor
2. In the **Layers** tab, select an image to define the map outline (opaque pixels = landmass, transparent = sea); the outline is extracted as an editable polygon
3. Drag vertices to reshape the outline, click an edge to insert a new vertex, or right-click a vertex to delete it
4. Add child layers and click **Subdivide** to split them into Voronoi regions; adjust point count, relaxation, and seed until the result looks right
5. In the **Metadata** tab, assign a custom schema script to the layer — it defines the typed properties each region holds (e.g. terrain, owner) and the rules for how those properties are rendered as colors; then use **Paint** mode to fill in values or **Inspect** mode to edit a region's full data
6. Configure the `ProvinceMap2D` node in the Inspector: select which layer and render mode to display, and set border style and color
7. At runtime, connect to `ProvinceMap2D` signals to detect which region was hovered or clicked, call `find_path` to run pathfinding between regions, or use the mutation API to update region data and trigger a redraw

See the [full documentation](https://oskarunn.gitlab.io/province-map-builder) for a detailed walkthrough and runtime API reference.

## License

MIT — see [LICENSE](LICENSE)

