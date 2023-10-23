# pgsql-omt-schema

From a osm2pgsql-imported rendering PostgreSQL+PostGIS database, serve omt-schema vectortiles

# Motivation

Already running a raster rendering osm stack ? These SQL functions make it
possible to also serve Mapbox
vector tiles
([MVT](https://docs.mapbox.com/data/tilesets/guides/vector-tiles-standards/))
in the openmaptiles vectortile schema
([omt-schema](https://openmaptiles.org/schema/)).
This can then be used by multiple styles to render beautiful vector maps in the
client browser.

### OMT styles

A little selection of styles
* [OSM](https://github.com/openmaptiles/openmaptiles/tree/master/style) an adaptation
of the raster [OSM Carto](https://github.com/gravitystorm/openstreetmap-carto) from the
homepage of [openstreetmap](https://www.openstreetmap.org).
* [OSM Bright](https://github.com/openmaptiles/osm-bright-gl-style)
* [Positron](https://github.com/openmaptiles/positron-gl-style)
* [MapTiler Basic](https://github.com/openmaptiles/maptiler-basic-gl-style)

# Requirements

* `python3`
  - `pip install psycopg2` for autodetecting tables and their columns in database
  - `pip install jinja2` for templating support, autodetected column names and types
  - `pip install sqlglot` for `--index` autogeneration, optional but highly recommended
for perfomance

* `osm2pgsql` was run with `--hstore` containing all missing tags. For now, a mix
of database columns and `tags->'colname'` accesses happen.
Maybe this can all be summarized in a `.style` file for osm2pgsql; but applying it
would require a reimport.

* Tables `*_point`, `*_line` and `*_polygon` exist,
 and you have these permissions:
  - `SELECT`,
  - `CREATE/DROP TYPE`,
  - `CREATE/DROP INDEX`,
  - `CREATE OR REPLACE FUNCTION`, and
  - `CREATE/DROP (MATERIALIZED) VIEW`
* The tables are found **by suffix**,
the prefix (default `planet_osm_*`) configured by `osm2pgsql` can be anything.
* All concerned geometry tables have their geometry column called `way`
  - (**planned**: just read `geometry_columns` table for the `way` column's name).


# Usage

### Create the SQL functions

`python3 run.py 'dbname=gis port=5432'`

this will output some `NOTICE`s...


At the end, a `length` with nonzero length should be generated if you have Switzerland
maps data at Weiningen (hardcoded `z/x/y` of `15/17151/11469`), else just a `length` of `0`.


### `pg_tileserv`
* install
[pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
and give it the database connection configuration.
* Important: Visit the `pg_tileserv` url root, and you should see `omt_all` under the
_Function Layers_ section (`pg_tileserv` needs to detect that is exists).

### Indexes

Then launch the index creation: they can speed up querying performance a little,
and will take up a minimal amount of disk space in the database
(about `600MB` for the planet, which is `<1%`).
On bigger databases it may take a long time
to run (up to 3h per piece on a planet database; around 25 of them, so up to 75h)

* If you want to read them through before:
* `python3 run.py 'dbname=gis port=5432' --index-print`


`python3 run.py 'dbname=gis port=5432' --index`

### Add tile url

Edit your map's `style.json` and replace the following:
```
    "sources": {
        "openmaptiles": {
          "type": "vector",
          "url": "https://api.maptiler.com/tiles/v3/tiles.json?key={key}"
        }
      },
```
with
```
    "sources": {
        "openmaptiles": {
          "type": "vector",
          "tiles": [
            "https:// _tileserv.your.server_ /public.omt_all/{z}/{x}/{y}.pbf"
          ],
          "maxzoom":15,
          "overzoom":1
        }
      },
```

### Overzoom

You may note the `"maxzoom":15,"overzoom":1` above, they allow to save some processing on the
server side for any zoom above 15. The functions are written to present all data
at zoom 15, and therefore higher-zoom tiles do not need to be generated if the client already has the z15.


This is called overzoom behaviour: the client keeps all z15 data and does not fetch anything
more at zooms 16, 17, 18, 19, 20, 21 and 22 (the vector tile limit).


The server does not need to generate or cache any data for these z16+ levels as well.

### Pre-rendering

The included script [mktiles.py](mktiles.py) can generate lower-zoom tiles into a directory.
Lower-zoom tiles contain data that changes rarely so they don't need to be rendered live.


These lower zoom tiles also need to query a lot of data and so take multiple seconds per tile
to generate, this is not comfortable for viewing.


`python3 mktiles.py 'dbname=gis port=5432' {z} {x} {y} {/path/to/file/cache}`

## Options

* `python3 run.py 'dbname=... ' --print` will just print the compiled template and not run anything
(Though it will connect to the database to read which columns exist or not)

* `python3 run.py 'dbname=... ' --index` will compile the template
and generate indexes on the database for speeding up lookup times during rendering.
Re-running will skip exising indexes (use `--index-drop` before to delete them).
Info: this will use some space in the database.


# Contours

Not the omt schema, but still a rich addition to any map: elevation, represented as same-elevation contour lines.


On a just somewhat related note: The `contours-function.sql` creates a `pg_tileserv`
compatible sql function that returns data from a contours lines database
([setup guide](https://wiki.openstreetmap.org/wiki/Contour_relief_maps_using_mapnik#The_PostGIS_approach)).
The supplied [`contours.json`](contours.json) is a simple style for that, adapted from the `contours.xml`
in the guide.

## Javascript

The contours layer alone is not useful. Add the following javascript to
"append" contours to an already existing layger :
```
document.map.on('load',function() {
  fetch('contours.json').then(r=>r.json()).then(function(c) {
    Object.keys(c.sources).forEach(k=>{
        document.map.addSource(k,c.sources[k]);
    });
    c.layers.forEach(l=>document.map.addLayer(l));
  });
});
```
_Note_ : Change `hostname` to your own in the sample `contours.json`.


_Note_ : Make sure that the `"sources":{}` section does not contain a source
name that conflicts with the underlying `style.json` (here `"openmaptiles"` vs `"contours"`)


# Dependencies for a full pipeline

* [osm2pgsql](https://github.com/osm2pgsql-dev/osm2pgsql) and a
[PostGIS](https://postgis.net/) enabled PostgreSQL database
* [pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
for serving the generated vector tiles
* _Recommended_ : a file caching server, especially for your low-zoom tiles that
can take a long time to generate.

# Disclaimer


Still not finished:
* some data needs to be queried from different tables (line,point,polygon) where it
currently only is queried from one
* `run.py` argparse clean up CLI API
* `run.py` add template configuration beyond just editing the source
* low-zoom tiles are way too big and slow
* see `TODO` comments in sql for more

### imposm3

Most guides to selfhost your own vectortiles recommend importing the database with
[imposm3](https://github.com/omniscale/imposm3).
But I found nothing when data is already imported with `osm2pgsql` except
for [this](https://github.com/MapServer/basemaps/blob/main/contrib/osm2pgsql-to-imposm-schema.sql)
set of SQL tables. But those are not written with realtime rendering in mind, nor
with updateability of the data (with `.osc` files).


These two tools produce a very different database table layout, and the main
aim of this SQL script is to adapt the `osm2pgsql` produced
tables for generating vectortiles, despite the omt-specification
only considering data from the `imposm3` schema.


Also, this "adapting" from one table layout to the other is difficult and will always be a
moving target. For now this script is best-effort and I try do document
differences. Changes requiring significant performance loss will probably not
be considered.

### Performance

This is a balance between tile serving speed and disk usage/efficiency.


Indexes only speed queries up by a little, but because they don't use that much space
compared to data, I still recommend using them.

### Feature parity


- Which features should be hidden in which order when zooming out is somewhat
unclear from the documentations. For now I go with what looks right.
- Aggregation: The layer `transportation` is currently being aggregated on its geometries,
and it shows to be an excellent way to reduce tilesize.
- Missing Feature: For the `buildings` layer as well: when zooming out, buildings, before all disappearing,
start to cluster into bigger chunks,
but only when there are a lot of buildings around.


### Out-of-specification behaviour

- The OSM Bright style uses `"name:latin"` and `"name:nonlatin"`, which is not in the spec.
Currently, `name_en` and `name_de` are not created, and only `name` is used.
To create `"name:latin"`, see template definition comments.
  * Another option to alias feature name data as "name:latin" data is to do so client-side.
See provided [`set_name_property.js`](set_name_property.js) sample.


- `ele_ft` column is omitted

- The `rank` column is not clearly documented and I am just tweaking numbers untils it looks
about right, for now.


