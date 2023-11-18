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

### Demo

[Browse the interactive vector map](https://feludwig.github.io/pgsql-omt-schema)
with all these [attributions](demo)


#### A little selection of omt-schema compatible styles
* featured in demo [OSM](https://github.com/openmaptiles/openmaptiles/tree/master/style) an adaptation
of the raster [OSM Carto](https://github.com/gravitystorm/openstreetmap-carto) from the
homepage of [openstreetmap](https://www.openstreetmap.org).
* featured in demo [OSM Bright](https://github.com/openmaptiles/osm-bright-gl-style)
* [Positron](https://github.com/openmaptiles/positron-gl-style)
* featured in demo [MapTiler Basic](https://github.com/openmaptiles/maptiler-basic-gl-style)

#### Vector tile advantages over raster tiles

* see [demo/main.js](demo/main.js) for samples
* names of cities/roads/POIs etc can be switched over to other language
  (or take local name and add english internationalized name in parens below)
* elevation data can be displayed in a richer way than "just" contours or hillshades:
  3D map "Add relief" button
* map can be rotated and name labels stay horizontal, on mobile with two fingers and on the computer
  with a right-click+hold-and-drag
* zoom levels are not discrete steps, but can be in a smooth range (eg z=15.68, impossible on raster).
  And the names/labels all scale continuously as well, instead of "jumping" in size like on a raster map


# Requirements

* `python3`
  - `pip install psycopg2` for autodetecting tables and their columns in database
  - `pip install jinja2` for templating support, autodetected column names and types
  - `pip install sqlglot` for `--index` autogeneration, optional but highly recommended
for a little more perfomance

* `osm2pgsql` was run with `--hstore` containing all missing tags. A mix
of database columns and `tags->'colname'` accesses are needed, and `tags` will be
the fallback if the column does not exist. A description
of all needed columns is in the [run.py](run.py) driver: `need_columns` and `aliases` variables.

* Need to import some additional static data
[at this point](#load-natural-earth-data),
Natural Earth tables `ne_10m_*`, `ne_50m_*`, `ne_110m_*`.
The already existing `ne_110m_admin_0_boundary_lines_land` will be overwritten with
the geometry column name `way` (mapnik raster rendering default).

* Table `water_polygons` exists and holds static data,
  as imported for use in the rendering pipeline
* Tables `*_point`, `*_line` and `*_polygon` exist,
 and you have these permissions:
  - `SELECT`,
  - `CREATE/DROP TYPE`,
  - `CREATE/DROP INDEX` (optional),
  - `CREATE OR REPLACE FUNCTION`, and
  - `CREATE/DROP TABLE` for NaturalEarth data
* The tables are found **by suffix**,
the prefix (default `planet_osm_*`) configured by `osm2pgsql` can be anything.
* All concerned geometry tables have their geometry column called `way`
  - (**planned**: just read `geometry_columns` table for the `way` column's name).
* Your data is in english, if you imported custom data in german for example, `'attraktion'` in the
  column `tourismus` will **not** be recognized as a `tourism=attraction` and be ignored.
  Feature names are obviously recognized, but using `nein` and `ja` instead of `no` and `yes` for
  boolean values like `indoor` is not planned for, and will fallback to `NULL` or false.


# Status

### Tile size across zoom

Zoom range|Server usability|Client usability
---|---|---
0-3|only `mktiles.py`, minutes to hours per tile|between 500KB/tile and ~1500KB/tile: usable
4-5|only `mktiles.py`, minutes to hours per tile|sometimes 1MB/tile but can be looked at
6-10|recommend file caching because multiple seconds to minutes to render,`mktiles.py` or `pg_tileserv`|rendering is responsive, <500KB/tile usually
11-15|live serving possible, size is usually <500KB/tile mapbox recommendation|rendering is responsive
16-22|no work to do|excellent: no need for network once z15 visited


See end of [demo/tile_generation.log](demo/tile_generation.log) file for more detailed and by-layer
size and extract time statistics. Landarea is counting tiles only by how much land they represent,
in the middle of the ocean that's 0% but e.g `4/7/5.pbf` covering
Ireland, UK and France is 19.629% landarea. And `4/11/5.pbf` covering Kazakhstan is 100% landarea.

When it takes multiple minutes per tile, `pg_tileserv` will just timeout.
And if there is too much data it makes some kind of I/O error

### Not finished

* `run.py` argparse clean up CLI API
* `run.py` template configuration: just editing the source is clumsy at best
* see `TODO` comments in sql
* see [Disclaimer](#Disclaimer)

# Dependencies for a full pipeline

* [osm2pgsql](https://github.com/osm2pgsql-dev/osm2pgsql) and a
[PostGIS](https://postgis.net/) enabled PostgreSQL database
* [pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
for serving the generated vector tiles
* _Recommended_ : a file caching server, especially for your low-zoom tiles that
can take a long time to generate.

# Dependencies at import

* [`ogr2ogr`](https://gdal.org/programs/ogr2ogr.html) from GDAL
* `sqlite3`
* `python3`

On a debian-based system:
```
sudo apt-get install wget python3 sqlite3 libgdal-dev
```

# Usage

### Load lake-centerline data

Static data [lake_centerline.geojson](lake_centerline.geojson) is from
<https://github.com/lukasmartinelli/osm-lakelines>

```
python3 run.py 'dbname=gis port=5432' --lake
```

### Load [Natural Earth](https://www.naturalearthdata.com/downloads/) data

Dependencies:
```
sudo apt-get install wget python3 sqlite3 libgdal-dev
```
Then
```
bash naturalearth_get.sh 'dbname=gis port=5432'
```


This downloads a 800MB zip of lowzoom Natural Earth data, extracts, converts
and imports it into the database.
It creates static tables `ne_10m_*`,`ne_50m_*`,`ne_110m_*` for various
layers at low zooms, like oceans for layer `water` or country+province boundaries for layer `boundary`.


### Create the SQL functions

```
python3 run.py 'dbname=gis port=5432'
```

this will print some `NOTICE`s...


At the end, a statistics table should be printed, with nonzero values if you have Switzerland
in the database (takes `z/x/y` from the center point of Switzerland),
else the test tile will just be `x=0, y=0` with probably empty data.


### `pg_tileserv`
* install
[pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
and give it the database connection configuration.
* Important: Visit the `pg_tileserv` url root, and you should see `omt_all` under the
_Function Layers_ section (`pg_tileserv` needs to detect that it exists).

### Indexes

Then launch the index creation: they can speed up querying performance a little,
and will take up a minimal amount of disk space in the database
(about `600MB` for the planet, which is `<1%`).
On bigger databases it may take a long time
to run (up to 1h30-2h per piece on a planet database;
there are around 25 of them, so up to 50h)

If you want to read them through before:
```python3 run.py 'dbname=gis port=5432' --index-print```

```
python3 run.py 'dbname=gis port=5432' --index
```

_Note_ : The index creation will block all writes to the currently indexing table.
Change `CREATE INDEX` to `CREATE INDEX CONCURRENTLY` if you wish to still write while
indexing. This has the tradeoff of being much slower (up to 3h per piece on a planet db)


_Note_ : In another shell, run

```
while sleep 1;do data="$(psql -d gis -p 5432 -c "select
  round((100*blocks_done)::numeric/nullif(blocks_total,0),2)::text||'%' as progress,
  pg_size_pretty(pg_relation_size(relid)) as tablesize,
  pg_size_pretty(pg_relation_size(index_relid)) as indexsize,command,phase,
  (select relname from pg_class where oid=index_relid) as indexname
from pg_stat_progress_create_index" --csv|tail -n1)";
printf '\033[2K\r%s' "${data}";done
```

for a live index creation progress report.

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

```
python3 mktiles.py 'dbname=gis port=5432' --range {/path/to/file/cache} {z} {x} {y}
```
or
```
python3 mktiles.py 'dbname=gis port=5432' --range {/path/to/file/cache} {z}-{zEnd} {xmin}-{xmax} {ymin}-{ymax}
```
or
```
python3 mktiles.py 'dbname=gis port=5432' --list {/path/to/file/cache} < tiles_to_generate
```

## Options

* `python3 run.py 'dbname=... ' --print` will just print the compiled template and not run anything
(Though it will connect to the database to read which columns exist or not)

* `python3 run.py 'dbname=... ' --index` will compile the template
and generate indexes on the database for speeding up lookup times during rendering.
Re-running will skip exising indexes (use `--index-drop` before to delete them).
Info: this will use some space in the database.


# Contours

Not the omt schema, but still a rich addition to any map: elevation, represented as same-elevation contour lines.


The `contours-function.sql` creates a `pg_tileserv`
compatible sql function that returns data from a contours lines database
([setup guide](https://wiki.openstreetmap.org/wiki/Contour_relief_maps_using_mapnik#The_PostGIS_approach)).
See [demo](#Demo) for implementation, with a stylesheet
[demo/styles/contours.json](demo/styles/contours.json), adapted from the `contours.xml` in that guide.
This is independent of the omt-schema.

## Javascript

The contours layer alone is not useful. Add the following javascript to
"append" contours to an already existing layer (present in [demo/main.js](demo/main.js)):
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


# Disclaimer

### imposm3

Most guides to selfhost your own vectortiles recommend importing the database with
[imposm3](https://github.com/omniscale/imposm3).
But I found nothing when data is already imported with `osm2pgsql` except
for [this](https://github.com/MapServer/basemaps/blob/main/contrib/osm2pgsql-to-imposm-schema.sql)
set of SQL tables. But those are not written with realtime rendering in mind, nor
with updateability of the data (with `.osc` files that `osm2pgsql` reads in).


These two tools produce a very different database table layout, and the main
aim of this SQL script is to adapt the `osm2pgsql` produced
tables for generating vectortiles, despite the omt-specification
only considering data from the `imposm3` schema.


Also, this "adapting" from one table layout to the other is difficult and will always be a
moving target. This script is best-effort and I try do document
differences. Changes requiring significant performance loss will probably not
be considered.

### Generalization

The process of simplifying and removing geometric features when displaying them at
low zooms: country polygons do not need to have multiple millions of points when
displayed at z4 where they take up around 100 pixels.
`imposm3` does generalization by itself and stores multiple copies of the data at different
generalization levels, but `osm2pgsql` does not. Here I attemt to craft generalization
algorithms by hand in sql. This is not a scaleable approach and a future approach would
be to make use of osm2pgsql's generalization features (though they are still in development
as of 2023).


One advantage of doing generalization like this is that the database does not store multiple
copies of geometries (a little disk space saved, but that's not worth too much).


### Performance

This is a balance between tile serving speed and disk usage/efficiency.


Indexes only speed queries up by a little, but because they don't use that much space
compared to data, I still recommend using them.

### Feature parity


- Which features should be hidden in which order when zooming out is somewhat
unclear from the omt-schema specification. For now I go with what looks right.
- Aggregation: The layers `transportation`,`landuse`, and `landcover`
are currently being aggregated on theirs geometries,
and it shows to be an excellent way to reduce tilesize.

- Missing Feature: For the `buildings` layer as well:
when zooming out, before all buildings disappear,
they start to cluster into bigger chunks;
but only when there are a lot of buildings around.


### Out-of-specification behaviour

- `ele_ft` column is omitted

- The `rank` column is not clearly documented and I am just tweaking numbers untils it looks
about right, for now. The OSM Bright style has some erratic behaviour on the poi layer with that,
it's showing almost nothing right now.

- Some styles use `"name:latin"` and `"name:nonlatin"`, which is not in the spec.
Currently, `name_en` and `name_de` are not created, and only `name` is used.
To create `"name:latin"`, see template definition comments.
  * Another option to alias feature `name` data as `"name:latin"` data is to do so client-side:
see provided [demo/main.js](demo/main.js), function `set_name_property` for a sample.

