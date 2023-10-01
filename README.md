# pgsql-omt-schema
From a osm2pgsql-imported rendering PostgreSQL+PostGIS database, serve omt-schema vectortiles

# Motivation

Already running a raster rendering osm stack ? These SQL functions make it
possible to also serve 
[MVT](https://docs.mapbox.com/data/tilesets/guides/vector-tiles-standards/)
vector tiles in the openmaptiles vectortile 
[schema](https://openmaptiles.org/schema/) .
This can then be used by multiple styles to render beautiful vector maps in the
client browser.

### OMT styles

A little selection of styles
* [OSM Bright](https://github.com/openmaptiles/osm-bright-gl-style)
* [Positron](https://github.com/openmaptiles/positron-gl-style)
* [MapTiler Basic](https://github.com/openmaptiles/maptiler-basic-gl-style)

# Requirements

* `osm2pgsql` was run with `--hstore` containing all missing tags. For now, a mix
of database columns and `tags->'colname'` accesses happen.
Maybe this can all be summarized in a `.style` file for osm2pgsql; but applying it
would require a reimport.

* Tables `planet_osm_point`, `planet_osm_line` and `planet_osm_polygon` exist,
are in the `public` schema and you have `SELECT` permissions.
Their geometry column is called `way`.


Also, lots of columns must exist and the script will just error out if they do
not exist. Usually `tags->'column_name'` will contain the data


**Planned**: generating indexes for all of these queries to make them faster,
will require permissions for `CREATE INDEX`.

# Dependencies for a full pipeline

* [osm2pgsql](https://github.com/osm2pgsql-dev/osm2pgsql) and a
[PostGIS](https://postgis.net/) enabled PostgreSQL database
* [pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
for serving the generated vector tiles
* _Recommended_ : a file caching server, especially for your low-zoom tiles that
can take a long time to generate.

# Disclaimer

EXPERIMENTAL


And this is even incomplete. A work in progress.

### imposm3

Most guides to selfhost your own vectortiles recommend importing the database with 
[imposm3](https://github.com/omniscale/imposm3).
But I found nothing when data is already imported with `osm2pgsql`.
These two tools produce a very different database schema, and the main
aim of this SQL script is to adapt a subset of the `imposm3` produced
schema for generating vectortiles, from the `osm2pgsql` schema.
Referring to the schema as one is incorrect, because both tools powerfully
allow configuring them.


But when the database was already imported with `osm2pgsql` ?


Or when the need for both mapnik.xml raster tiles and vectortiles comes up ?
Is one supposed to host two complete copies of the same data ?


Also, this "adapting" from one schema to the other is difficult and will always be a
moving target. For now this script is best-effort and I try do document
differences. Changes requiring significant performance loss will probably not
be considered.

### Performance

This is a balance between tile serving speed and disk usage/efficiency.
Importing data with `imposm3` directly for your vectortile needs will
usually be faster when serving clients. But the aim here is to make `osm2pgsql`-imported
databases competitive and more versatile in the same situation.


**Planned** Indexes should somewhat speed up queries. Though I still need to check how much
additional space they can take up

### Feature parity

Geometries are currently just returned from the database. This is very wasteful
for low zooms where a `ST_SimplifyPreserveTopology(geometry,200)` should be used.


Which features should be hidden in which order when zooming out is somewhat
unclear from the documentations. For now I go with what looks right.


Aggregating geometries on low zooms. This looks to be a feature when zooming
out: buildings, before all disappearing, start to cluster in bigger chunks;
but only when there are a lot of buildings around. This is not planned for
implementation.


### Name columns

The OSM Bright style uses `"name:latin"` and `"name:nonlatin"`, which is not in the spec.
Currently, `name_en` and `name_de` are not created, and `name` is used for `"name:latin"`
unconditionally (this is temporary).

# Usage

### Create the SQL functions

`psql -d gis -f pgsql-omt-schema/omt-functions.sql`


this should output a lot of `CREATE FUNCTION`s.


If your database schema is unexpected, an error will show up.
At the end, a `length` with nonzero length should be generated if you have Switzerland
maps data for Weiningen (hardcoded z/x/y of 16,34303,22938).
This should also not produce an error.


If everything worked, you can:
* install
[pg\_tileserv](https://github.com/CrunchyData/pg_tileserv)
and give it the database connection configuration.
* Visit the pg\_tileserv url root, and you should see `omt_all` under the 
_Function Layers_ section.

### Add tile url

Edit the `style.json` and replace the following:


    "sources": {
        "openmaptiles": {
          "type": "vector",
          "url": "https://api.maptiler.com/tiles/v3/tiles.json?key={key}"
        }
      },


with

    "sources": {
        "openmaptiles": {
          "type": "vector",
          "tiles": [
            "https://tileserv.your.server/public.omt_all/{z}/{x}/{y}.pbf"
          ]
        }
      },

