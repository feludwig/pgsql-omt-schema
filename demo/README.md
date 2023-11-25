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

And I added some adjustments:
* show an `orange_dot` or `purple_dot` for restaurants/shops respectively at z14, like raster style
* and hide names at those z14-z17. Also with more finegrained icon resolving for specific classes
* correct colour of `bus_stop_square`, and change zoom-behaviour similarly
to `orange_dot` and `purple_dot`
* various additional sprites:
  - ref shield for `class=trunk` (`road_trunk`) in `transportation_name`
  - `fountain` in `poi`
  - duplicate `diy` to `doityourself`, inconsistent naming in the data...
* `mountain_peak` text format when elevation is null: do not show stray "m"
* manually setting `class=pitch` in layer `landuse` to be over `class=residential`, not under
* `tower_obervation` and more specific towers, refined from `viewpoint`
* `class=information` specificities like `subclass=guidepost` or `subclass=board` in `poi`
* show pois more aggressively even at low zooms
* miscellaneous zoom-stepping (newer syntax with `["step",["zoom"],"",15,["get","name"]]`)


The sprites are also incompatible with spritezero in some environments, regarding embedding
href="data:text/base64,aaaaaa" binary data inline: for putting a png into an svg.
This is the case for `wetland_mangrove` and similar. Using `ffmpeg` and then `spritezero-png`
works, but involves generating sprites twice individually (for `@2x.png` and `.png`).

### osm-bright

<https://github.com/openmaptiles/osm-bright-gl-style>


Basic starting style for omt-schema stylesheets, published by
[OpenMapTiles](https://openmaptiles.org/styles/).


Has a horrible rank out-of-specification behaviour: filter based on 15 < rank < 25 !?
This then hides almost all pois on high zoom

### maptiler-basic

<https://github.com/openmaptiles/maptiler-basic-gl-style>


Basic starting style for omt-schema stylesheets, published by
[OpenMapTiles](https://openmaptiles.org/styles/).

### cyclo-bright

See cyclo-routes below

<https://github.com/leonardehrenfried/cyclo-bright-gl-style>


An addition to the [osm-bright](#osm-bright) stylesheet

### cyclo-routes

A subset of the above [cyclo-bright](#cyclo-bright), mostly the additions. Used as an overlay

### contours

I did a raster to vector adaptation of
<https://wiki.openstreetmap.org/wiki/Contour_relief_maps_using_mapnik#The_PostGIS_approach>

## Fonts

<https://github.com/openmaptiles/fonts>
