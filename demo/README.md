# Browse

<https://feludwig.github.io/pgsql-omt-schema>


# Attribution

I wrote the javascript `demo/main.js` including the following features :
* `set_name_property` adapt the style's uses of `"name:latin"` to the data's `name`
* `switch_style_over` select a style in the dropdown
* `add_geojson_playground`, `add_click_listener` one big advantage of vector maps
over raster is that you can directly click on a feature: this just shows the data from
the tile and displays the geometry in magenta colour (in the `playground` layer)
* `enable_contours` check on or off: draw an overlay of contours vector tiles
* `add_relief` not currently available, but: show mountain shape data as 3d relief
 **TODO** add exaggeration, something like 2.5

The styles in `styles/` are mostly not my work :

### openstreetmap-vector

<https://github.com/openmaptiles/openmaptiles/tree/master/style>

which is an adaptation of the raster stylesheet

<https://github.com/gravitystorm/openstreetmap-carto>

And I added a few adjustments:
* show an `orrange_dot` or `purple_dot` for restaurants/shops respectively at z15, like raster style
* `mountain_peak` text format when elevation is null
* miscellaneous zoom-stepping (newer syntax with `["step",["zoom"],"",15,["get","name"]]`)

### osm-bright

<https://github.com/openmaptiles/osm-bright-gl-style>

### maptiler-basic

<https://github.com/openmaptiles/maptiler-basic-gl-style>

### cyclo-bright

<https://github.com/leonardehrenfried/cyclo-bright-gl-style>

### contours

I did a raster to vector adaptation of
<https://wiki.openstreetmap.org/wiki/Contour_relief_maps_using_mapnik#The_PostGIS_approach>

## Fonts

<https://github.com/openmaptiles/fonts>
