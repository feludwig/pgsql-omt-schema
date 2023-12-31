--  (c) This file is part of pgsql-omt-schema
--  see https://github.com/feludwig/pgsql-omt-schema for details
--  Author https://github.com/feludwig
--
--   LICENSE https://github.com/feludwig/pgsql-omt-schema/blob/main/LICENSE
--   GPL v3 in short :
--     Permissions of this strong copyleft license are conditioned on making available
--     complete source code of licensed works and modifications, which include larger
--     works using a licensed work, under the same license.
--     Copyright and license notices must be preserved.

-- TEMPLATE usage:
-- need to define variables in run.py, then
-- syntax is: {% if with_osm_id %} SQL STATEMENT1 {% else %} SQL STATEMENT2 {% endif %}
--    where with_osm_id is a boolean variable
-- other syntax: {{ omt_func_pref }}
--    where omt_func_pref is a text variable

-- IMPORTANT: raster z11==vector z10, rz11=z10 in short. rz04=z03, rz05=z04
-- WARNING: only one curly brace pair used in this explanation to not confuse templating engine, use 2 pairs
-- VARIABLES available :
--  {point} the table storing all point features, default osm2pgsql name planet_osm_point
--    -> FROM {point.table_name}
--    -> SELECT {point.<column_name>} FROM ...
--        this becomes "(tags->'col') AS col" when col was not detected in db, and "col AS col" otherwise
--    -> WHERE {point.<col>_v}*2==7 AND ... [v for "value"] removes the "AS"
--        this becomes "(tags->'col')" when col was not detected, and "col" otherwise
--    -> WHERE {point.<col>_ne} OR ... [ne for "not exists"] tests IS NULL
--        this becomes "(NOT (tags?'col'))" when col was not detected, and "col IS NULL" otherwise
--    -> WHERE {point.<col>_e} OR ... [e for "exists"] tests IS NOT NULL
--        opposite of <col>_ne
--  {line} the table storing all line features, default osm2pgsql name planet_osm_line
--    -> exaclty like {point}, there is a {line.table_name} and
--    -> {line.<col>}, {line.<col>_v}, {line.<col>_e}, {line.<col>_ne}
--  {polygon} the table storing all line features, default osm2pgsql name planet_osm_polygon
--    -> exaclty like {point}, there is a {polygon.table_name} and
--    -> {polygon.<col>}, {polygon.<col>_v}, {polygon.<col>_e}, {polygon.<col>_ne}
--  ALSO: any column name {point.<colname>_ct} ["coalesce tag"] gets expanded to:
--    COALESCE(point."colname",point."tags"->'colname') AS colname
--  AND its counterpart {point.<colname>_ctv} ["coalesce tag value"] :
--    COALESCE(point."colname",point."tags"->'colname')


-- TODO:
--  * water z<=07 do not simplify anymore? OR ST_MakeValid!!!
--  -> benchmark tile 7/110/52 and 7/111/51
--  * move all table names to templated table names
--  * transportation minimum tolerance for st_collectoverlapping ? to join the
--      two lanes of motorways into one at z<10
--      This procedure is more complicated... maybe a st_dumppoints+st_voronoilines...
--      For now, just take both lanes of a highway
--  * transportation_name route_1,2,3,4,5,6 columns? aggregate over gemetries and
--      something.. CASE NOT NULL?
--  * building color column...? IS NULL everywhere for now
--  * poi agg_stop column IS NULL by default


-- implementation details:
--  see https://wiki.postgresql.org/wiki/Inlining_of_SQL_functions#Inlining_conditions_for_table_functions
--  for why this is mostly LANGUAGE 'sql' and not 'plpgsql'
DROP TYPE IF EXISTS {{omt_typ_pref}}_aerodrome_label CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_aeroway CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_boundary CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_building CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_housenumber CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_landcover CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_landuse CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_mountain_peak CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_park CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_place CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_poi CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_waterway CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_transportation CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_transportation_name CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_water CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_water_name CASCADE;

-- united types to make {layer} and {layer}_name
DROP TYPE IF EXISTS {{omt_typ_pref}}_transportation_merged CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_water_merged CASCADE;



-- BEWARE! the order of these columns is important.
-- if you exchange two differently-typed columns, postgresql will not be happy,
-- but the danger is when you exchange two same-type columns: postgresql will
-- happily resturn you the wrong results...
CREATE TYPE {{omt_typ_pref}}_transportation AS (
{% if with_osm_id %} osm_id text, {% endif %}
  class text,
  subclass text,
  network text,
  brunnel text,
  oneway int,
  ramp int,
  service text,
  access boolean,
  toll int,
  expressway int,
{% if transportation_with_cycleway %}
  cycleway int,
{% endif %}
  layer int,
  level text,
  indoor int,
  bicycle text,
  foot text,
  horse text,
  mtb_scale text,
  surface text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_transportation_name AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  ref text,
  --ref_length int, -- WARN:IS MISSING!, added later on
  network text,
  -- WARN: oder diff from transportation
  class text,
  subclass text,
  brunnel text,
  level text,
  layer int,
  indoor int,
  -- MISSING: route_x !!!
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_transportation_merged AS (
  tablefrom text,
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  ref text,
  class text,
  subclass text,
  network text,
  brunnel text,
  oneway int,
  ramp int,
  service text,
  access boolean,
  toll int,
  expressway int,
{% if transportation_with_cycleway %}
  --EXTENSION:
  cycleway int,
{% endif %}
  layer int,
  level text,
  indoor int,
  bicycle text,
  foot text,
  horse text,
  mtb_scale text,
  surface text,
  geom geometry
);


CREATE TYPE {{omt_typ_pref}}_aerodrome_label AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  class text,
  iata text,
  icao text,
  ele integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_aeroway AS (
{% if with_osm_id %} osm_id text, {% endif %}
  ref text,
  class text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_boundary AS (
{% if with_osm_id %} osm_id text, {% endif %}
  admin_level integer,
  adm0_l text,
  adm0_r text,
  disputed integer,
  disputed_name text,
  claimed_by text,
  maritime integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_building AS (
  render_height real,
  render_min_height real,
  --colour text, -- in format '#rrggbb' TODO!
  hide_3d boolean,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_housenumber AS (
  housenumber text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_landcover AS (
{% if with_osm_id %} osm_id text, {% endif %}
  class text,
  subclass text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_landuse AS (
{% if with_osm_id %} osm_id text, {% endif %}
  class text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_mountain_peak AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  class text,
  ele integer,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_park AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  class text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_place AS (
{% if place_with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  capital integer,
  class text,
  iso_a2 text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_poi AS (
{% if poi_with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  class text,
  subclass text,
  rank integer,
  agg_stop integer,
  level int,
  layer int,
  indoor int,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_water_merged AS (
  -- needed for get_lakeline lookup
  osm_id bigint,
  name text,
  {{name_columns_typ}}
  class text,
  intermittent integer,
  brunnel text,
-- exceptionally, return the full geometry way, NOT the not yet truncated ST_AsMVTGeom()
  way geometry,
--get_lakeline does not work on node osm_ids, but still needs to differenciate way/rel osm_ids
  tablefrom text
);

CREATE TYPE {{omt_typ_pref}}_water AS (
{% if with_osm_id %} osm_id text, {% endif %}
  class text,
  intermittent integer,
  brunnel text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_water_name AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  {{name_columns_typ}}
  class text,
  intermittent integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_waterway AS (
  name text,
  {{name_columns_typ}}
  class text,
  brunnel text,
  intermittent integer,
  geom geometry
);



--utilities
CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_real_null(data text) RETURNS real
AS $$
SELECT CASE
  WHEN data~E'^\\d+(\\.\\d+)?$' THEN data::real
  WHEN data~E'^\\.\\d+$' THEN ('0'||data)::real -- '.9'::text -> '0.9'::text -> 0.9::real
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_landcover_simplified(way geometry)
RETURNS geometry
AS $$
  WITH dp(g) AS (SELECT (ST_Dump(way)).geom)
  SELECT ST_Union(ST_BuildArea(ST_ExteriorRing(dp.g))) FROM dp;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_int_null(data text) RETURNS integer
AS $$
SELECT CASE
  WHEN data~E'^\\d+$' THEN data::integer
    -- also accept spaces within the number ['g' for global: replace ALL matches]
  WHEN data~E'^(\\d+\\s*)+$' THEN regexp_replace(data,E'\\s','','g')::integer
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_rank_by_area(area real) RETURNS int
AS $$
SELECT CASE WHEN v.val<1 THEN 1 ELSE v.val END
  FROM (SELECT -1*log(20.0,area::numeric)::int+10 AS val) AS v;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_start_date_year(start_date text) RETURNS int
AS $$
-- see https://wiki.openstreetmap.org/wiki/Key:start_date
SELECT CASE
  WHEN regexp_match(start_date,E'^jd:') IS NOT NULL THEN NULL -- ignore julian day jd:2455511
  WHEN {{omt_func_pref}}_text_to_int_null((regexp_match(start_date,E'[0-9]{4}'))[1]) IS NOT NULL
    THEN {{omt_func_pref}}_text_to_int_null((regexp_match(start_date,E'[0-9]{4}'))[1])
  -- 'C13' means 13th century, 'mid C14' reduced to C14 for simplicity
  WHEN {{omt_func_pref}}_text_to_int_null((regexp_match(start_date,E'C([0-9]{2})'))[1]) IS NOT NULL
    THEN ({{omt_func_pref}}_text_to_int_null((regexp_match(start_date,E'C([0-9]{2})'))[1])-1)*100
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_place_multiplier(class text) RETURNS int
AS $$
SELECT CASE class
  WHEN 'continent' THEN 12
  WHEN 'country' THEN 11
  WHEN 'state' THEN 10
  WHEN 'province' THEN 9
  WHEN 'city' THEN 8
  WHEN 'town' THEN 7
  WHEN 'island' THEN 6
  WHEN 'village' THEN 5
  WHEN 'suburb' THEN 4
  WHEN 'quarter' THEN 3
  WHEN 'neighbourhood' THEN 2
  WHEN 'hamlet' THEN 1
  WHEN 'isolated_dwelling' THEN 0
  ELSE 0
END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_lakeline(way geometry,
    test_id bigint) RETURNS geometry
AS $$
-- INPUT: way a polygon of a lake, or river
-- OUTPUT: a lakeline, to use for placong text on the polygon.
--WITH a(a) AS (
--    SELECT ST_Dump(ST_ApproximateMedialAxis(way))),
--  b(sum,geom) AS (
--    SELECT SUM(ST_Intersects((a1.a).geom,(a2.a).geom)::int),(a1.a).geom
--    FROM a AS a1, a AS a2 WHERE (a1.a).path[1]>(a2.a).path[1]
--    GROUP BY a1.a),
--  c(geom) AS (
--    SELECT ST_LineMerge(unnest(ST_ClusterIntersecting(geom)))
--    FROM b WHERE sum>1)
--SELECT ST_MakeLine(geom) FROM c;
BEGIN
IF (SELECT count(*) FROM lake_centerline WHERE osm_id=test_id)!=0 THEN
  RETURN (SELECT l.way FROM lake_centerline AS l WHERE l.osm_id=test_id);
ELSIF NOT ST_Intersects(way,ST_Buffer(
          ST_Transform(ST_SetSRID(ST_GeomFromText('LINESTRING(-180 89.999, -180 -89.999)'),4326),3857),
        0.1)) THEN
  -- take p as pointonsurface. then return the line that is parallel to
  --  way's st_longestline but also
  --  crosses p. This is to ensure a "croissant" shaped lake will have its lakeline
  --  across itself and not across the land. see osm_id=r3173129 or osm_id=r5864238
  --  for how a longestline alone is not enough
  RETURN (WITH
      pt(g) AS(SELECT ST_PointOnSurface(way)),
      p(x,y) AS(SELECT ST_X(pt.g),ST_Y(pt.g) FROM pt),
      l(g) AS (SELECT ST_LongestLine(way,way)),
      ps(x,y) AS (SELECT ST_X(ST_StartPoint(l.g)),ST_Y(ST_StartPoint(l.g)) FROM l),
      pe(x,y) AS (SELECT ST_X(ST_EndPoint(l.g)),ST_Y(ST_EndPoint(l.g)) FROM l),
      ll(g) AS (SELECT ST_MakeLine(ARRAY[
        ST_Point(p.x-pe.x+ps.x,p.y-pe.y+ps.y,ST_SRID(way)),
        ST_Point(p.x+pe.x-ps.x,p.y+pe.y-ps.y,ST_SRID(way))
      ]) FROM p,ps,pe)
  -- take intersection with way to cut out any over-land parts
        SELECT ST_Intersection(ll.g,way) FROM ll
  );
-- something special for lake names crossing the dateline
ELSE
  RETURN (WITH lines_dump AS (
      SELECT ST_LongestLine((ST_Dump(way)).geom,(ST_Dump(way)).geom) AS l)
    SELECT l FROM lines_dump
    ORDER BY ST_Length(l) DESC LIMIT 1
  );
END IF;
END
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

{% if make_name_columns_function %}
CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_name_lang(tags hstore,iso2_lang text) RETURNS text
AS $$
  SELECT (tags->('name:'||iso2_lang));
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;
{% endif %}

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landuse(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landuse
AS $$
SELECT
{% if with_osm_id %}
  array_to_string((array_agg(DISTINCT CASE
    WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END))[1:5],',') AS osm_id,
{% endif %}
  (CASE
    WHEN {{polygon.landuse_v}} IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail') THEN {{polygon.landuse_v}}
    WHEN {{polygon.amenity_v}} IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') THEN
      CASE {{polygon.amenity_v}} WHEN 'grave_yard' THEN 'cemetery' ELSE {{polygon.amenity_v}} END
    WHEN {{polygon.leisure_v}} IN ('stadium','pitch','playground','track') THEN {{polygon.leisure_v}}
    WHEN {{polygon.tourism_v}} IN ('theme_park','zoo') THEN {{polygon.tourism_v}}
    WHEN {{polygon.place_v}} IN ('suburbquarter','neighbourhood') THEN {{polygon.place_v}}
    WHEN {{polygon.waterway_v}} IN ('dam') THEN {{polygon.waterway_v}}
  END) AS class,
  ST_SimplifyPreserveTopology(ST_AsMVTGeom(ST_UnaryUnion(unnest(ST_ClusterIntersecting(
    (CASE
        WHEN z>=11 THEN way
        WHEN z=10 THEN ST_Buffer(way,60)
        WHEN z=09 THEN ST_Buffer(way,120)
        WHEN z=08 THEN ST_Buffer(way,250)
        WHEN z=07 THEN ST_Buffer(way,500)
        WHEN z=06 THEN ST_Buffer(way,1e3)
        ELSE NULL
    END)
  ))),bounds_geom {{bounds_geom_options}}),10) AS geom
FROM {{polygon.table_name}}
WHERE ({{polygon.landuse_v}} IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail')
  OR {{polygon.leisure_v}} IN ('stadium','pitch','playground','track')
  OR {{polygon.tourism_v}} IN ('theme_park','zoo') OR {{polygon.place_v}} IN ('suburbquarter','neighbourhood')
  OR {{polygon.amenity_v}} IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') OR {{polygon.waterway_v}} IN ('dam')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
    (z>=13) OR
    (z=12 AND {{polygon.way_area_v}}>1500) OR
    (z=11 AND {{polygon.way_area_v}}>6000) OR
    (z=10 AND {{polygon.way_area_v}}>24e3) OR
    (z=09 AND {{polygon.way_area_v}}>96e3) OR
    (z=08 AND {{polygon.way_area_v}}>384e3) OR
    (z=07 AND {{polygon.way_area_v}}>1536e3) OR
    (z=06 AND {{polygon.way_area_v}}>6e6) -- empty at lower zooms
  )
GROUP BY(class);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_aerodrome_label(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_aerodrome_label
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
    name, {{name_columns_run}}
    (CASE WHEN aerodrome_type IN ('international','public','regional','miltary','private','other')
      THEN aerodrome_type
      ELSE 'other' -- remove any NULLs
    END) AS class,
    iata,icao,{{omt_func_pref}}_text_to_int_null(ele) AS ele,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||{{point.osm_id_v}}) AS osm_id, {% endif %}
    {{point.tags}},
    {{point.name}},{{point.aeroway_v}},{{point.aerodrome_type}},
    {{point.iata}},{{point.icao}},{{point.ele}},{{point.way}}
  FROM {{point.table_name}}
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
{% endif %}
    {{polygon.tags}},
    {{polygon.name}},{{polygon.aeroway_v}},{{polygon.aerodrome_type}},
    {{polygon.iata}},{{polygon.icao}},{{polygon.ele}},{{polygon.way}}
  FROM {{polygon.table_name}}
) AS foo
WHERE aeroway='aerodrome' AND ST_Intersects(way,bounds_geom) AND z>=08;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_aeroway(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_aeroway
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  ref,class,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||{{point.osm_id_v}}) AS osm_id, {% endif %}
    {{point.ref}},{{point.aeroway_v}} AS class,{{point.way}}
  FROM {{point.table_name}}
  WHERE {{point.aeroway_v}} IN ('gate')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
    WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
{% endif %}
    {{line.ref}},{{line.aeroway_v}} AS class,{{line.way}}
  FROM {{line.table_name}}
  WHERE {{line.aeroway_v}} IN ('runway','taxiway')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
{% endif %}
    {{polygon.ref}},{{polygon.aeroway_v}} AS class,{{polygon.way}}
  FROM {{polygon.table_name}}
  WHERE {{polygon.aeroway_v}} IN ('aerodrome','heliport','runway','helipad','taxiway','apron')
    ) AS foo
WHERE ST_Intersects(way,bounds_geom) AND (z>=09);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landcover(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landcover
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  ( CASE -- resolve the class from the subclass
    WHEN subclass IN ('farmland', 'farm', 'orchard', 'vineyard', 'plant_nursery' ) THEN 'farmland'
    WHEN subclass IN ('glacier', 'ice_shelf' ) THEN 'ice'
    WHEN subclass IN ('wood', 'forest' ) THEN 'wood'
    WHEN subclass IN ('bare_rock', 'scree' ) THEN 'rock'
    WHEN subclass IN ('fell', 'grassland', 'heath', 'scrub', 'shrubbery',
      'tundra', 'grass', 'meadow', 'allotments', 'park', 'village_green',
      'recreation_ground', 'garden', 'golf_course' ) THEN 'grass'
    WHEN subclass IN ('wetland', 'bog', 'swamp', 'wet_meadow', 'marsh', 'reedbed',
      'saltern', 'tidalflat', 'saltmarsh', 'mangrove' ) THEN 'wetland'
    WHEN subclass IN ('beach', 'sand', 'dune' ) THEN 'sand'
  END ) AS class,subclass,
  ST_SimplifyPreserveTopology(ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}),
    CASE WHEN z<=09 THEN 10 WHEN z=05 THEN 15 WHEN z=04 THEN 20
    WHEN z=03 THEN 25
    WHEN z<=02 THEN 30
    ELSE 5 END) AS geom
FROM (SELECT
{% if with_osm_id %}
  array_to_string((array_agg(DISTINCT CASE
    WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END))[1:5],',') AS osm_id,
{% endif %}
    ( CASE
      WHEN {{polygon.landuse_v}} IN ('allotments','farm','farmland','orchard','plant_nursery','vineyard',
        'grass','grassland','meadow','forest','village_green','recreation_ground') THEN {{polygon.landuse_v}}
      WHEN {{polygon.natural_v}} IN ('wood','wetland','fell','grassland','heath','scrub','shrubbery','tundra',
      'glacier','bare_rock','scree','beach','sand','dune') THEN {{polygon.natural_v}}
      WHEN {{polygon.leisure_v}} IN ('park','garden','golf_course') THEN {{polygon.leisure_v}}
      WHEN {{polygon.wetland_v}} IN ('bog','swamp','wet_meadow','marsh','reedbed','slatern','tidalflat',
        'saltmarsh','mangrove') THEN {{polygon.wetland_v}}
      ELSE NULL
    END ) AS subclass,
  ST_UnaryUnion(unnest(ST_ClusterIntersecting(CASE
        WHEN z>=11 THEN way
        WHEN z=10 THEN ST_Buffer(way,30)
        WHEN z=09 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,60))
        WHEN z=08 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,120))
        WHEN z=07 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,250))
        WHEN z=06 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,600))
        WHEN z=05 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,1.2e3))
        WHEN z=04 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,3e3))
        WHEN z=03 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,7e3))
        WHEN z=02 THEN {{omt_func_pref}}_get_landcover_simplified(ST_Buffer(way,16e3))
        ELSE NULL
    END))) AS way
  FROM {{polygon.table_name}}
  WHERE ({{polygon.landuse_v}} IN ('allotments','farm','farmland','orchard','plant_nursery','vineyard',
    'grass','grassland','meadow','forest','village_green','recreation_ground')
  OR {{polygon.natural_v}} IN ('wood','wetland','fell','grassland','heath','scrub','shrubbery','tundra',
    'glacier','bare_rock','scree','beach','sand','dune')
  OR {{polygon.leisure_v}} IN ('park','garden','golf_course')
  OR {{polygon.wetland_v}} IN ('bog','swamp','wet_meadow','marsh','reedbed','slatern','tidalflat','saltmarsh','mangrove')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
    (z>=14)
    OR (z=13 AND {{polygon.way_area_v}}>1500)
    OR (z=12 AND {{polygon.way_area_v}}>6000)
    OR (z=11 AND {{polygon.way_area_v}}>25e3)
    OR (z=10 AND {{polygon.way_area_v}}>130e3)
    OR (z=09 AND {{polygon.way_area_v}}>600e3)
    OR (z=08 AND {{polygon.way_area_v}}>1e6)
    OR (z=07 AND {{polygon.way_area_v}}>1.8e6)
      -- polar regions! srid=8857 is area-preserving and area_8857~=area_3857 at EQUATOR ONLY
      -- for performance: check way_area a tenth smaller too
    OR (z=06 AND {{polygon.way_area_v}}>800e2 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>800e3)
    OR (z=05 AND {{polygon.way_area_v}}>1e5 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>1.7e6)
    OR (z=04 AND {{polygon.way_area_v}}>2e5 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>2.1e6)
    OR (z=03 AND {{polygon.way_area_v}}>4e5 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>4e6)
    OR (z=02 AND {{polygon.way_area_v}}>7e5 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>7e6)
    -- show nothing at lower zooms
  )
  GROUP BY(subclass)
  UNION
  SELECT
{% if with_osm_id %} 'icesh_polygs' AS osm_id, {% endif %}
    'glacier' AS subclass,
    ST_Union(way) AS way
  FROM icesheet_polygons WHERE ST_Intersects(icesheet_polygons.way,bounds_geom)
) AS foo
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION {{omt_func_pref}}_building(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_building
AS $$
SELECT {{omt_func_pref}}_text_to_real_null({{polygon.height_v}}) AS render_height,
  COALESCE(
    {{omt_func_pref}}_text_to_real_null({{polygon.min_height_v}}),
    {{omt_func_pref}}_text_to_real_null({{polygon.building_levels_v}})*2.5
  )::real AS render_min_height,
  --'#ffff00' AS colour,
  (CASE
    WHEN {{polygon.building_part_v}} IS NULL THEN true
    WHEN {{polygon.building_part_v}} IN ('no') THEN false
    ELSE NULL END) AS hide_3d,
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom {{bounds_geom_options}}) AS geom
FROM {{polygon.table_name}}
WHERE {{polygon.building_e}}
  AND (NOT {{polygon.location_v}} ~ 'underground' OR {{polygon.location_ne}})
  AND ST_Intersects({{polygon.way_v}},bounds_geom)
  AND (
    (z>=14 OR {{polygon.way_area_v}}>=200) AND (z>12) -- show no buildings above z>=12
  );
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_park(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_park
AS $$
SELECT
{% if with_osm_id %}
  array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
  name,{{name_columns_aggregate_run}} class,
  (row_number() OVER (ORDER BY sum(way_area) DESC))::int AS rank,
  ST_SimplifyPreserveTopology(
    ST_AsMVTGeom(ST_UnaryUnion(unnest(ST_ClusterIntersecting(way))),bounds_geom {{bounds_geom_options}}),
   8) AS geom
FROM (
  SELECT
  {% if with_osm_id %}
    (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
      WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
  {% endif %}
    {{polygon.tags}}, -- for name languages
    (CASE
      WHEN z<=12 AND {{polygon.way_area_v}}<3e5 THEN NULL
      ELSE {{polygon.name_v}}
    END) AS name,
    (CASE
      WHEN {{polygon.boundary_v}}='aboriginal_lands' THEN {{polygon.boundary_v}}
      ELSE COALESCE(replace(lower(NULLIF({{polygon.protection_title_v}},'')),' ','_'),
        NULLIF({{polygon.boundary_v}},''),NULLIF({{polygon.leisure_v}},''))
    END) AS class,
    {{polygon.way}},{{polygon.way_area}}
  FROM {{polygon.table_name}}
  WHERE ({{polygon.boundary_v}} IN ('national_park','protected_area')
      OR {{polygon.leisure_v}}='nature_reserve')
    AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
      --same as landcover
    (z>=14)
    OR (z=13 AND {{polygon.way_area_v}}>1500)
    OR (z=12 AND {{polygon.way_area_v}}>6000)
    OR (z=11 AND {{polygon.way_area_v}}>25e3)
    OR (z=10 AND {{polygon.way_area_v}}>130e3)
    OR (z=09 AND {{polygon.way_area_v}}>600e3)
    OR (z=08 AND {{polygon.way_area_v}}>1e6)
    OR (z=07 AND {{polygon.way_area_v}}>1.8e6)
  )) AS foo
WHERE (z>=07)
GROUP BY(class,name);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_mountain_peak(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_mountain_peak
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  name, {{name_columns_subquery_propagate}} class,ele,rank,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
FROM (
  SELECT
  {% if with_osm_id %} osm_id, {% endif %}
    name, {{name_columns_run}} class,ele,
    (row_number() OVER (ORDER BY 10000*score+(CASE WHEN
          ele IS NULL THEN 0 ELSE ele END) DESC))::int AS rank,
    --also take score up: for zoom filtering
    score,way
  FROM (
    SELECT
  {% if with_osm_id %} ('n'||{{point.osm_id_v}}) AS osm_id, {% endif %}
      {{point.tags}},
      {{point.name}},{{omt_func_pref}}_text_to_int_null({{point.ele_ctv}}) AS ele,
      -- score of 3 means popular item: should be shown first
      ({{point.name_e}}::int+{{point.wikipedia_e}}::int+{{point.wikidata_e}}::int) AS score,
      {{point.natural_v}} AS class,{{point.way}}
    FROM {{point.table_name}}
    WHERE {{point.natural_v}} IN ('peak','volcano','saddle')
    UNION ALL
    SELECT
  {% if with_osm_id %}
    (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
      WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
  {% endif %}
      {{line.tags}},
      {{line.name}},{{omt_func_pref}}_text_to_int_null({{line.ele_ctv}}) AS ele,
      -- score of 3 means popular item: should be shown first
      ({{line.name_e}}::int+{{line.wikipedia_e}}::int+{{line.wikidata_e}}::int) AS score,
      {{line.natural_v}} AS class,{{line.way}}
    FROM {{line.table_name}}
    WHERE {{line.natural_v}} IN ('ridge','cliff','arete')
      ) AS united_point_line
  WHERE ST_Intersects(way,bounds_geom)
) AS zoom_unfiltered
WHERE (z>=14)
  OR (z>=11 AND z<14 AND rank<=30) -- limit to X features per tile
  OR (z<11 AND score=3 AND class IN ('peak') AND rank<=30) -- only wikipedia-existing 'peak's
;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_post_agg_boundary(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_boundary
-- pre_country: with not-yet set adm0_l and adm0_r columns, and the ORIGINAL way geometry
AS $$
SELECT
{% if with_osm_id %}
  (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
    WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
{% endif %}
  {{line.admin_level_v}}::integer AS admin_level,
  NULL AS adm0_l,NULL AS adm0_r,
  (CASE WHEN {{line.disputed_v}} IN ('yes') OR {{line.boundary_v}} IN ('disputed') THEN 1
  END) AS disputed,
  {{line.disputed_name}},
  (CASE {{line.admin_level_v}} WHEN '2' THEN
    COALESCE({{line.iso3166_1_alpha2_v}},{{line.iso3166_1_v}},
      {{line.country_code_fips_v}},{{line.country_code_iso3166_1_alpha_2_v}})
    ELSE NULL END) AS claimed_by,
  (CASE {{line.boundary_v}} WHEN 'maritime' THEN 1 ELSE 0 END) AS maritime,
  {{line.way_v}} AS geom -- WARNING: abusive cast, still ST_AsMVTGeom(geom) missing
FROM {{line.table_name}}
WHERE {{line.boundary_v}} IN ('administrative','disputed') AND (
    (z>=11)
    --OR (z<11 AND {{line.admin_level_v}} IN ('1','2','3','4','5','6','7'))
    OR (z<11 AND z>= 8 AND {{line.admin_level_v}} IN ('1','2','3','4','5','6'))
    OR (z< 8 AND z>= 7 AND {{line.admin_level_v}} IN ('1','2','3','4'))
    -- switch to naturalearth data at z06 and less
  ) AND ST_Intersects({{line.way_v}},bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


{% macro query_osmdata_boundary() %}
WITH osmdata_boundary AS (
  SELECT
{% if with_osm_id %}
    array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
    admin_level,
    NULL AS adm0_l,NULL AS adm0_r,
    disputed,disputed_name,claimed_by,maritime,
    ST_AsMVTGeom(
      ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2)),
      bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{omt_func_pref}}_post_agg_boundary(bounds_geom,z)
  WHERE z>=07
  GROUP BY(admin_level,disputed,disputed_name,claimed_by,maritime)
) SELECT
{% if with_osm_id %} osm_id, {% endif %}
  admin_level,adm0_l,adm0_r,disputed,disputed_name,claimed_by,maritime,
  ST_SimplifyPreserveTopology(geom,10) AS geom
FROM osmdata_boundary
{% endmacro %}
{% macro union_query_naturalearth_always_boundary() %}
UNION
-- ne_10m_admin_0_boundary_lines_maritime_indicator: "indicator" means not the full EEZ,
--  only a suggestive line between two ambiguously near landmasses... see DK/SE for example
--  REMOVE the medianline_83 whatever it is...
--  03<=z all the way to z20
SELECT
{% if with_osm_id %} 'ne_'||(ne_id::text) AS osm_id, {% endif %}
  2 AS admin_level,NULL AS adm0_l,NULL AS adm0_r,
  0 AS disputed,NULL AS disputed_name,NULL AS claimed_by,1 AS maritime,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
FROM ne_10m_admin_0_boundary_lines_maritime_indicator
WHERE note !~ 'medianLine' AND ST_Intersects(way,bounds_geom) AND z>=03 AND z>=(min_zoom+2)
UNION
-- do something with ne_10m_admin_0_disputed_areas
SELECT
{% if with_osm_id %} 'ne_'||(ne_id::text) AS osm_id, {% endif %}
  2 AS admin_level,NULL AS adm0_l,NULL AS adm0_r,
  1 AS disputed,COALESCE(brk_group,name) AS disputed_name,
  adm0_a3 AS claimed_by,0 AS maritime,
  ST_AsMVTGeom(ST_Boundary(way),bounds_geom {{bounds_geom_options}}) AS geom
  FROM ne_10m_admin_0_disputed_areas
-- ignore min_zoom column because boundary might show up as undisputed else
WHERE ST_Intersects(way,bounds_geom)
{% endmacro %}

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_boundary(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_boundary
AS $$
BEGIN
  IF z>=07 THEN
      -- SELECT ... [and then add UNION SELECT other stuff]
    RETURN QUERY
      {{query_osmdata_boundary()}}
      {{union_query_naturalearth_always_boundary()}} ;
  ELSE -- z<=06
    RETURN QUERY
--  00<=z<=02 ne_110m_admin_0_pacific_groupings
SELECT
{% if with_osm_id %} 'ne_fid'||(ogc_fid::text) AS osm_id, {% endif %}
  2 AS admin_level,NULL AS adm0_l,NULL AS adm0_r,
  0 AS disputed,NULL AS disputed_name,NULL AS claimed_by,1 AS maritime,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
FROM ne_110m_admin_0_pacific_groupings
WHERE ST_Intersects(way,bounds_geom) AND z<=02
-- ne_10m_admin_0_boundary_lines_land : [admin_level=2]
-- 00<=z<=01: ne_110m
--  02<=z<=04: ne_50m
--  05<=z<=06: ne_10m
--  07<=z: osm_boundaries
--    ===AND===
-- ne_10m_admin_1_states_provinces_lines : [admin_level=4]
-- z>=07 AND z>=04: ne_10m
-- z>=01 AND z<=03: ne_50m
-- z=00: nothing
{% for admin_level,do_maritime_test,z_cond,tbl_name in (
  (2,'','z<=01','ne_110m_admin_0_boundary_lines_land'),
  (2,'','z>=02 AND z<=04','ne_50m_admin_0_boundary_lines_land'),
  (2,'','z>=05 AND z<=06','ne_10m_admin_0_boundary_lines_land'),
  (4,'ne_50m_ocean','z>=01 AND z<=03','ne_50m_admin_1_states_provinces_lines'),
  (4,'ne_10m_ocean','z>=04 AND z<=06','ne_10m_admin_1_states_provinces_lines'),
  ) %}
UNION
SELECT
{% if with_osm_id %} 'ne_'||(ne_id::text) AS osm_id, {% endif %}
  {{admin_level}} AS admin_level,
  {% if tbl_name == 'ne_10m_admin_0_boundary_lines_land' %}
  -- data does not exist in other tables
  adm0_a3_l AS adm0_l,adm0_a3_r AS adm0_r,
  {% else %}
  NULL AS adm0_l,NULL AS adm0_r,
  {% endif %}
  0 AS disputed,NULL AS disputed_name,NULL AS claimed_by,
  {% if do_maritime_test != '' %}
    bool_or(ST_Equals(
        {{tbl_name}}.way,
        ST_Intersection({{tbl_name}}.way,ocean.way)
    ))::int AS maritime,
  {% else %}
    0 AS maritime,
  {% endif %}
  ST_AsMVTGeom({{tbl_name}}.way,bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{tbl_name}}
  {% if do_maritime_test != '' %}
  , {{do_maritime_test}} AS ocean
  {% endif %}
  WHERE ST_Intersects({{tbl_name}}.way,bounds_geom) AND {{z_cond}}
  {% if do_maritime_test != '' %}
  GROUP BY({{tbl_name}}.ogc_fid)
  {% endif %}
{% endfor %}
{{union_query_naturalearth_always_boundary()}} ;
  END IF;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_housenumber(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_housenumber
AS $$
SELECT housenumber,
  ST_AsMVTGeom((CASE
      WHEN tablefrom = 'point' THEN way
      ELSE ST_PointOnSurface(way) END),bounds_geom {{bounds_geom_options}}) AS geom
FROM (
  SELECT {{line.housenumber}},{{line.way}},'line' AS tablefrom,{{line.demolished_building}}
  FROM {{line.table_name}}
  UNION ALL
  SELECT {{point.housenumber}},{{point.way}},'point' AS tablefrom,{{point.demolished_building}}
  FROM {{point.table_name}}
  UNION ALL
  SELECT {{polygon.housenumber}},{{polygon.way}},'polygon' AS tablefrom,
  {{polygon.demolished_building}}
  FROM {{polygon.table_name}})
    AS layer_housenumber
  -- obviously don't scan on the ST_PointOnSurface(way) because those are not indexed
WHERE housenumber IS NOT NULL AND (demolished_building='no' OR demolished_building IS NULL)
  AND ST_Intersects(way,bounds_geom) AND z>=14;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_pre_agg_transportation_merged(
    bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation_merged
AS $$
SELECT tablefrom,
{% if with_osm_id %} osm_id, {% endif %}
  name, {{name_columns_run}} ref,class,
  (CASE WHEN class IN ('bicycle_route') THEN network
    ELSE subclass END) AS subclass,
  network,brunnel,oneway,ramp,
  service,access,toll,expressway,
  {% if transportation_with_cycleway %} cycleway, {% endif %}
  layer,level,
  indoor,bicycle,foot,horse,mtb_scale,surface,
  geom
FROM (
  SELECT
    'line' AS tablefrom,
{% if with_osm_id %}
  (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
    WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
{% endif %}
    {{line.tags}},{{line.name}},{{line.ref}},
  -- from https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
    (CASE
      WHEN {{line.highway_v}} = 'construction' THEN (CASE
          WHEN {{line.construction_v}} IN ('motorway','motorway_link') THEN 'motorway_construction'
          WHEN {{line.construction_v}} IN ('trunk','trunk_link') THEN 'trunk_construction'
          WHEN {{line.construction_v}} IN ('primary','primary_link') THEN 'primary_construction'
          WHEN {{line.construction_v}} IN ('secondary','secondary_link') THEN 'secondary_construction'
          WHEN {{line.construction_v}} IN ('tertiary','tertiary_link') THEN 'tertiary_construction'
          WHEN {{line.construction_v}} IN ('minor','minor_link') THEN 'minor_construction'
          ELSE 'minor_construction' -- when OTHERs
        END)
      WHEN {{line.highway_v}} IN ('motorway','trunk','primary','secondary','tertiary',
        'service','track','raceway') THEN {{line.highway_v}}||(CASE WHEN {{line.construction_e}}
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      WHEN {{line.highway_v}} IN ('unclassified','residential','living_street') THEN 'minor'||(
        CASE WHEN {{line.construction_e}}
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      WHEN {{line.highway_v}} IN ('road') OR {{line.route_v}} IN ('road') THEN 'unknown'
      WHEN {{line.highway_v}} IN ('motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')
        THEN substring({{line.highway_v}},'([a-z]+)')
      WHEN {{line.route_v}} IN ('bicycle') THEN 'bicycle_route' --NOTE:extension
      WHEN {{line.highway_v}} IN ('cycleway','path','pedestrian','footway','steps') THEN 'path'||(
        CASE WHEN {{line.construction_v}} IS NOT NULL
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      -- and now non-highways
      WHEN {{line.railway_v}} IN ('rail','narrow_gauge','preserved','funicular') THEN 'rail'
      WHEN {{line.railway_v}} IN ('subway','light_rail','monorail','tram') THEN 'transit'
      WHEN {{line.aerialway_e}} THEN 'aerialway'
      WHEN {{line.shipway_e}} THEN {{line.shipway_v}}
      WHEN {{line.man_made_e}} THEN {{line.man_made_v}}
      WHEN {{line.public_transport_e}} THEN {{line.public_transport_v}}
      WHEN {{line.route_v}} IN ('ferry') THEN 'ferry'
      WHEN {{line.route_v}} IN ('hiking') THEN 'path'
      WHEN {{line.service_v}} IN ('driveway','parking_aisle') THEN 'service'
    END) AS class,
    (CASE
      WHEN {{line.railway_e}} THEN {{line.railway_v}}
      WHEN {{line.public_transport_e}} AND {{line.public_transport_v}}!=''
        THEN {{line.public_transport_v}}
      WHEN {{line.highway_e}} THEN {{line.highway_v}}
      WHEN {{line.aerialway_e}} THEN {{line.aerialway_v}}
      WHEN {{line.man_made_e}} THEN {{line.man_made_v}}
      WHEN {{line.route_e}} THEN {{line.route_v}}
      WHEN {{line.service_e}} THEN {{line.service_v}}
    END) AS subclass,
    (CASE WHEN {{line.route_v}} IN ('bicycle') THEN
      (CASE {{line.network_v}} WHEN 'icn' THEN 'international'
        WHEN 'ncn' THEN 'national'
        WHEN 'rcn' THEN 'regional'
        WHEN 'lcn' THEN 'local'
      END) --NOTE:extension
      ELSE NULLIF({{line.network_v}},'') END) AS network,
    (CASE
      WHEN ({{line.bridge_v}} IS NOT NULL AND {{line.bridge_v}}!='no')
        OR {{line.man_made_v}}='bridge' THEN 'bridge'
      WHEN {{line.tunnel_v}} IS NOT NULL AND {{line.tunnel_v}}!='no' THEN 'tunnel'
      WHEN {{line.ford_v}} IS NOT NULL AND {{line.ford_v}}!='no' THEN 'ford'
    END) AS brunnel,
    (CASE
        -- instead of 0 because no one checks ==0 nor !=0, just ==1 or ==-1. NULL then can
        -- aggregate with all other oneway==NULLs
      WHEN {{line.oneway_v}} IN ('no') THEN NULL
      WHEN {{line.oneway_v}} IN ('-1') THEN -1
      WHEN {{line.oneway_v}} IS NOT NULL THEN 1
      WHEN {{line.oneway_v}} IN ('alternating') THEN 2
      ELSE NULL
    END) AS oneway,
    (CASE
      WHEN {{line.ramp_v}} IN ('no','separate') THEN 0
      WHEN {{line.ramp_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS ramp,
    NULLIF({{line.service_v}},'') AS service,
    CASE WHEN access IN ('no','private') THEN false ELSE NULL END AS access,
    (CASE
      WHEN {{line.toll_v}} IN ('no') THEN 0
      WHEN {{line.toll_e}} THEN 1
      ELSE NULL
    END) AS toll,
    (CASE
      WHEN {{line.expressway_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS expressway,
{% if transportation_with_cycleway %}
-- TODO: this is just a boolean; why not rewrite cycle-routes.json; should be simpler
    (CASE WHEN {{line.bicycle_v}} IN ('yes','1','designated','permissive') THEN 1
      WHEN {{line.bicycle_v}} IN ('no','dismount') THEN 0 ELSE NULL
      --TODO: why not tags->'cycleway' &+ tags->'cycleway:left' and tags->'cycleway:right' ?
    END) AS cycleway, --NOTE: extension
{% endif %}
    {{line.layer}},
    {{line.level}},
    (CASE WHEN {{line.indoor_v}} IN ('yes','1') THEN 1 END) AS indoor,
    -- also CHECK tracktypes! in style they look like asphalt roads
    NULLIF({{line.bicycle_v}},'') AS bicycle,
    NULLIF({{line.foot_v}},'') AS foot,
    NULLIF({{line.horse_v}},'') AS horse,
    NULLIF({{line.mtb_scale_v}},'') AS mtb_scale,
    (CASE WHEN {{line.surface_v}} IN ('paved','asphalt','cobblestone','concrete',
        'concrete:lanes','concrete:plates','metal','paving_stones','sett',
        'unhewn_cobblestone','wood') THEN 'paved'
      WHEN {{line.surface_v}} IN ('unpaved','compacted','dirt','earth','fine_gravel',
        'grass','grass_paver','grass_paved','gravel','gravel_turf','ground',
        'ice','mud','pebblestone','salt','sand','snow','woodchips') THEN 'unpaved'
    END) AS surface,
    ST_AsMVTGeom({{line.way_v}},bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{line.table_name}}
  WHERE (
    {{line.railway_v}} IN ('rail','narrow_gauge','preserved','funicular','subway','light_rail',
      'monorail','tram')
    -- hide link bits above zoom 12
    OR ({{line.highway_v}} IN ('motorway_link','trunk_link','primary_link','secondary_link',
      'tertiary_link') AND z>=12)
    OR {{line.highway_v}} IN ('motorway','trunk','primary',
      'pedestrian','bridleway','corridor','service','track','raceway','busway',
      'bus_guideway','construction',
      'path','footway','cycleway','steps',
      'unclassified','residential','living_street',
      'tertiary','road','secondary')
    OR {{line.aerialway_v}} IN ('chair_lift','drag_lift','platter','t-bar','gondola','cable_bar',
      'j-bar','mixed_lift')
    OR {{line.route_v}} IN ('ferry','road','hiking')
    OR {{line.public_transport_v}} IN ('platform')
    OR {{line.man_made_v}} IN ('pier')
    OR {{line.service_v}} IN ('driveway','parking_aisle')
    OR {{line.route_v}} IN ('bicycle') --NOTE:extension
  ) AND ST_Intersects({{line.way_v}},bounds_geom)
  UNION SELECT
    'polygon' AS tablefrom,
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
{% endif %}
    {{polygon.tags}},{{polygon.name}},{{polygon.ref}},
    (CASE
      WHEN {{polygon.highway_v}} IN ('cycleway','path','pedestrian','footway','steps','bridleway','corridor')
        THEN 'path'||(CASE
          WHEN {{polygon.construction_v}} IS NOT NULL
          AND {{polygon.construction_v}} !='no' THEN '_construction' ELSE '' END)
        -- WARNING: nonstandard, or rather undefined behaviour: class="pier", "bridge" undocumented
        --    used in osm-bright style, id="road_area_pier" and id="road_area_bridge"...
      WHEN {{polygon.man_made_e}} THEN {{polygon.man_made_v}}
      WHEN {{polygon.public_transport_v}} IN ('platform') THEN 'path'
    END) AS class,
    (CASE
      WHEN {{polygon.public_transport_e}} AND {{polygon.public_transport_v}}!=''
        THEN {{polygon.public_transport_v}}
      WHEN {{polygon.highway_e}} THEN {{polygon.highway_v}}
      WHEN {{polygon.man_made_e}} THEN {{polygon.man_made_v}}
    END) AS subclass,
    NULLIF({{polygon.network_v}},'') AS network,
    (CASE
      WHEN ({{polygon.bridge_v}} IS NOT NULL AND {{polygon.bridge_v}}!='no')
        OR {{polygon.man_made_v}}='bridge' THEN 'bridge'
      WHEN {{polygon.tunnel_v}} IS NOT NULL AND {{polygon.tunnel_v}}!='no' THEN 'tunnel'
      WHEN {{polygon.ford_v}} IS NOT NULL AND {{polygon.ford_v}}!='no' THEN 'ford'
    END) AS brunnel,
    (CASE
      -- see line table above
      WHEN {{polygon.oneway_v}} IN ('no') THEN NULL
      WHEN {{polygon.oneway_v}} IN ('-1') THEN -1
      WHEN {{polygon.oneway_v}} IS NOT NULL THEN 1
      WHEN {{polygon.oneway_v}} IN ('alternating') THEN 2
      ELSE NULL
    END) AS oneway,
    (CASE
      WHEN {{polygon.ramp_v}} IN ('no','separate') THEN 0
      WHEN {{polygon.ramp_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS ramp,
    NULLIF({{polygon.service_v}},'') AS service,
    CASE WHEN access IN ('no','private') THEN false ELSE NULL END AS access,
    (CASE
      WHEN {{polygon.toll_v}} IN ('no') THEN 0
      WHEN {{polygon.toll_e}} THEN 1
      ELSE NULL
    END) AS toll,
    (CASE
      WHEN {{polygon.expressway_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS expressway,
{% if transportation_with_cycleway %}
    (CASE WHEN {{polygon.bicycle_v}} IN ('yes','1','designated','permissive') THEN 1
      WHEN {{polygon.bicycle_v}} IN ('no','dismount') THEN 0 ELSE NULL
    END) AS cycleway, --NOTE: extension
{% endif %}
    {{polygon.layer}},
    {{polygon.level}},
    (CASE WHEN {{polygon.indoor_v}} IN ('yes','1') THEN 1 END) AS indoor,
    -- also CHECK tracktypes! in style they look like asphalt roads
    NULLIF({{polygon.bicycle_v}},'') AS bicycle,
    NULLIF({{polygon.foot_v}},'') AS foot,
    NULLIF({{polygon.horse_v}},'') AS horse,
    NULLIF({{polygon.mtb_scale_v}},'') AS mtb_scale,
    (CASE WHEN {{polygon.surface_v}} IN ('paved','asphalt','cobblestone','concrete',
        'concrete:lanes','concrete:plates','metal','paving_stones','sett',
        'unhewn_cobblestone','wood') THEN 'paved'
      WHEN {{polygon.surface_v}} IN ('unpaved','compacted','dirt','earth','fine_gravel',
        'grass','grass_paver','grass_paved','gravel','gravel_turf','ground',
        'ice','mud','pebblestone','salt','sand','snow','woodchips') THEN 'unpaved'
    END) AS surface,
    ST_AsMVTGeom({{polygon.way_v}},bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{polygon.table_name}}
  WHERE (
    {{polygon.man_made_v}} IN ('bridge','pier')
    OR {{polygon.public_transport_v}} IN ('platform')
    OR {{polygon.highway_v}} IN ('path','cycleway','bridleway','footway','corridor','pedestrian','steps')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom)
  UNION SELECT
    'point' AS tablefrom,
{% if with_osm_id %}
  (CASE WHEN {{point.osm_id_v}}<0 THEN 'r'||(-{{point.osm_id_v}})
    WHEN {{point.osm_id_v}}>0 THEN 'w'||{{point.osm_id_v}} END) AS osm_id,
{% endif %}
    {{point.tags}},{{point.name}},{{point.ref}},
    (CASE
      WHEN {{point.highway_v}} IN ('motorway_junction') THEN 'motorway'
    END) AS class,
    {{point.highway_v}} AS subclass,
    NULLIF({{point.network_v}},'') AS network,
    (CASE
      WHEN ({{point.bridge_v}} IS NOT NULL AND {{point.bridge_v}}!='no')
        OR {{point.man_made_v}}='bridge' THEN 'bridge'
      WHEN {{point.tunnel_v}} IS NOT NULL AND {{point.tunnel_v}}!='no' THEN 'tunnel'
      WHEN {{point.ford_v}} IS NOT NULL AND {{point.ford_v}}!='no' THEN 'ford'
    END) AS brunnel,
    (CASE
      --see line above
      WHEN {{point.oneway_v}} IN ('no') THEN NULL
      WHEN {{point.oneway_v}} IN ('-1') THEN -1
      WHEN {{point.oneway_v}} IS NOT NULL THEN 1
      WHEN {{point.oneway_v}} IN ('alternating') THEN 2
      ELSE NULL
    END) AS oneway,
    (CASE
      WHEN {{point.ramp_v}} IN ('no','separate') THEN 0
      WHEN {{point.ramp_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS ramp,
    NULLIF({{point.service_v}},'') AS service,
    CASE WHEN access IN ('no','private') THEN false ELSE NULL END AS access,
    (CASE
      WHEN {{point.toll_v}} IN ('no') THEN 0
      WHEN {{point.toll_e}} THEN 1
      ELSE NULL
    END) AS toll,
    (CASE
      WHEN {{point.expressway_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS expressway,
{% if transportation_with_cycleway %}
    (CASE WHEN {{point.bicycle_v}} IN ('yes','1','designated','permissive') THEN 1
      WHEN {{point.bicycle_v}} IN ('no','dismount') THEN 0 ELSE NULL
    END) AS cycleway, --NOTE: extension
{% endif %}
    {{point.layer}},
    {{point.level}},
    (CASE WHEN {{point.indoor_v}} IN ('yes','1') THEN 1 END) AS indoor,
    -- also CHECK tracktypes! in style they look like asphalt roads
    NULLIF({{point.bicycle_v}},'') AS bicycle,
    NULLIF({{point.foot_v}},'') AS foot,
    NULLIF({{point.horse_v}},'') AS horse,
    NULLIF({{point.mtb_scale_v}},'') AS mtb_scale,
    (CASE WHEN {{point.surface_v}} IN ('paved','asphalt','cobblestone','concrete',
        'concrete:lanes','concrete:plates','metal','paving_stones','sett',
        'unhewn_cobblestone','wood') THEN 'paved'
      WHEN {{point.surface_v}} IN ('unpaved','compacted','dirt','earth','fine_gravel',
        'grass','grass_paver','grass_paved','gravel','gravel_turf','ground',
        'ice','mud','pebblestone','salt','sand','snow','woodchips') THEN 'unpaved'
    END) AS surface,
    ST_AsMVTGeom({{point.way_v}},bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{point.table_name}}
  WHERE (z>=10) AND {{point.highway_v}} IN ('motorway_junction')
    AND ST_Intersects({{point.way_v}},bounds_geom)
) AS unfiltered_zoom
WHERE (
     (z>=12 AND class IS NOT NULL) -- take everything
  OR (z>=11 AND substring(class,'([a-z]+)') IN ('tertiary','minor'))
  OR (z>=10 AND substring(class,'([a-z]+)') IN ('transit'))
  OR (z>=09 AND substring(class,'([a-z]+)') IN ('secondary','raceway','busway','aerialway'))
  OR (z>=08 AND substring(class,'([a-z]+)') IN ('primary'))
  OR (z>=07 AND substring(class,'([a-z]+)') IN ('ferry','rail'))
  OR (z>=04 AND substring(class,'([a-z]+)') IN ('motorway','trunk'))
    --extension
  OR (z>=08 AND class='bicycle_route' AND network='national')
  OR (z>=11 AND class='bicycle_route' AND network='local')
  OR (z>=10 AND class='bicycle_route' AND network='regional')
);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_z_low_10(
    bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation
AS $$
-- motivation: merge more columns together, because at z>=10 names of
-- roads are not shown anyways, nor bridges etc...
-- delete/disregard brunnels+layer
WITH aa AS (
    SELECT * FROM {{omt_func_pref}}_pre_agg_transportation_merged(bounds_geom,z)),
  aa_line AS (SELECT * FROM aa WHERE tablefrom='line'),
  aa_rest AS (SELECT * FROM aa WHERE tablefrom!='line')
{% for cte_name,geom_agg_run in (
  ('aa_line','ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterWithin(geom,10)),2))'),
  ('aa_rest','ST_UnaryUnion(unnest(ST_ClusterIntersecting(geom)))'))
  %}
{% if loop.index>1 %} --indexing starts at 1
  UNION --separator between loops
{% endif %}
SELECT
{% if with_osm_id %}
    array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
  class,subclass,
  NULL AS network,NULL AS brunnel,
  NULL::int AS oneway,NULL::int AS ramp,NULL AS service,
  NULL::bool AS access,max(toll) AS toll,
  max(expressway) AS expressway,
  {% if transportation_with_cycleway %} max(cycleway) AS cycleway, {% endif %}
  NULL::int AS layer,NULL AS level, NULL::int AS indoor,
  NULL AS bicycle,NULL AS foot,NULL AS horse,
  NULL AS mtb_scale,(array_agg(DISTINCT surface))[1] AS surface,
  ST_SimplifyPreserveTopology({{geom_agg_run}},
    CASE WHEN z>=09 THEN 10 WHEN z=08 THEN 17 WHEN z<=07 THEN 32
      END) AS geom
FROM {{cte_name}}
GROUP BY(class,subclass)
{% endfor %}
;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_name_z_low_10(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation_name
AS $$
-- motivation: merge more columns together, see transportation_z_low_10
-- and name not shown anymore, since z<13
WITH aa AS (
    SELECT * FROM {{omt_func_pref}}_pre_agg_transportation_merged(bounds_geom,z)),
  aa_line AS (SELECT * FROM aa WHERE tablefrom='line'),
  aa_rest AS (SELECT * FROM aa WHERE tablefrom!='line')
{% for cte_name,geom_agg_run in (
  ('aa_line','ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterWithin(geom,10)),2))'),
  ('aa_rest','ST_UnaryUnion(unnest(ST_ClusterIntersecting(geom)))')) %}
{% if loop.index>1 %} --indexing starts at 1
  UNION --separator between loops
{% endif %}
SELECT
{% if with_osm_id %}
{% if transportation_aggregate_osm_id_reduce %}
  (CASE WHEN (array_agg(DISTINCT name))[1] IS NULL THEN NULL
    --LIMIT 5 but that's a syntax error in an aggregate
    ELSE array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',')
  END) AS osm_id,
{% else %}
  array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
{% endif %}
  NULL AS name, {{name_columns_null}} ref,
  (array_agg(DISTINCT network))[1] AS network,class,subclass,
  NULL AS brunnel,
  (array_agg(DISTINCT level))[1] AS level,max(layer) AS layer,
  max(indoor) AS indoor,
  ST_SimplifyPreserveTopology({{geom_agg_run}},15) AS geom
FROM {{cte_name}}
WHERE ref IS NOT NULL AND (
  (z<=09 AND class IN ('motorway')) -- at z<=09, only show motorway refs
  OR (z>09 AND z<=10 AND class IN ('motorway','primary','trunk')))
GROUP BY(class,subclass,ref)
{% endfor %}
;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_highz(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation
AS $$
WITH aa AS (
    SELECT * FROM {{omt_func_pref}}_pre_agg_transportation_merged(bounds_geom,z)),
  aa_line AS (SELECT * FROM aa WHERE tablefrom='line'),
  aa_rest AS (SELECT * FROM aa WHERE tablefrom!='line')
{% for cte_name,geom_agg_run in (
  ('aa_line','ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2))'),
  ('aa_rest','ST_UnaryUnion(unnest(ST_ClusterIntersecting(geom)))')) %}
{% if loop.index>1 %} --indexing starts at 1
  UNION --separator between loops
{% endif %}
SELECT
{% if with_osm_id %}
  --LIMIT 5 but that's a syntax error in an aggregate
  array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
  class,subclass,
  (array_agg(DISTINCT network))[1] AS network,brunnel,
  oneway,min(ramp) AS ramp,(array_agg(DISTINCT service))[1] AS service,
  access,max(toll) AS toll,max(expressway) AS expressway,
  {% if transportation_with_cycleway %} cycleway, {% endif %}
  layer,(array_agg(DISTINCT level))[1] AS level,
  max(indoor) AS indoor,bicycle,
  (array_agg(DISTINCT foot))[1] AS foot,(array_agg(DISTINCT horse))[1] AS horse,
  (array_agg(DISTINCT mtb_scale))[1] AS mtb_scale,(array_agg(DISTINCT surface))[1] AS surface,
  {{geom_agg_run}} AS geom
FROM {{cte_name}}
-- deduce that a road MAY be candidate for merging if :
--  same name, class and ref accross geometry features
--  FILTER OUT bridge or tunnel segments (those will be rendered differently)
--  FILTER OUT access and oneway: a normal road can become oneway and still have the same name
--  FILTER OUT layer, similar reasoning like bridge/tunnel: renders sections of road diff
--  DO NOT FILTER OUT: indoor: because how would that happen anyways ?
-- then do the merging with unnest(ST_ClusterIntersecting())::multigeometries
-- ST_CollectionExtract(*,2) extracts only line features, ST_LineMerge then merges these
--  multigeometries to single geometries
GROUP BY(name,class,subclass,ref,brunnel,oneway,access,layer,
  {% if transportation_with_cycleway %} cycleway, {% endif %}
  bicycle)
{% endfor %}
;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_name_highz(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation_name
AS $$
WITH aa AS (
    SELECT * FROM {{omt_func_pref}}_pre_agg_transportation_merged(bounds_geom,z)),
  aa_line AS (SELECT * FROM aa WHERE tablefrom='line'),
  aa_rest AS (SELECT * FROM aa WHERE tablefrom!='line')
{% for cte_name,geom_agg_run in (
  ('aa_line','ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2))'),
  ('aa_rest','ST_UnaryUnion(unnest(ST_ClusterIntersecting(geom)))')) %}
{% if loop.index>1 %} --indexing starts at 1
  UNION --separator between loops
{% endif %}
SELECT
{% if with_osm_id %}
{% if transportation_aggregate_osm_id_reduce %}
  (CASE WHEN (array_agg(DISTINCT name))[1] IS NULL THEN NULL
    ELSE array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',')
  END) AS osm_id,
{% else %}
  array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',')
{% endif %}
{% endif %}
  name, {{name_columns_subquery_aggregate_propagate}} ref,
  (array_agg(DISTINCT network))[1] AS network,
  class,subclass,(array_agg(DISTINCT brunnel))[1] AS brunnel,
  (array_agg(DISTINCT level))[1] AS level,max(layer) AS layer,
  max(indoor) AS indoor,
  {{geom_agg_run}} AS geom
FROM {{cte_name}}
WHERE name IS NOT NULL OR ref IS NOT NULL
-- deduce that a road MAY be candidate for merging if :
--  same name, class and ref accross geometry features
-- then do the merging with unnest(ST_ClusterIntersecting())::multigeometries
-- ST_CollectionExtract(*,2) extracts only line features, ST_LineMerge then merges these
--  multigeometries to single geometries
GROUP BY(name,class,subclass,ref)
{% endfor %}
;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_name(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation_name
AS $$
BEGIN
IF (z<=07) THEN
  RETURN; -- empty at low zoom levels
ELSIF (z<=10) THEN
  RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_name_z_low_10(bounds_geom,z);
ELSE
  RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_name_highz(bounds_geom,z);
END IF;
END
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_transportation
AS $$
BEGIN
  IF (z<=04) THEN
    RETURN; -- 0 rows, empty at lowest zoom levels
  ELSIF (z<=10) THEN
    RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_z_low_10(bounds_geom,z);
  ELSE
    RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_highz(bounds_geom,z);
END IF;
END
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_waterway(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_waterway
AS $$
SELECT name, {{name_columns_aggregate_run}} class,
  (CASE WHEN z<=10 THEN NULL ELSE brunnel END) AS brunnel,intermittent,
  ST_SimplifyPreserveTopology(ST_AsMVTGeom(
    ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(way)),2)),
    --ST_UnaryUnion(unnest(ST_ClusterIntersecting(way))),
    bounds_geom {{bounds_geom_options}}),CASE WHEN z>=09 THEN 0
      WHEN z=08 THEN 10 WHEN z=07 THEN 15 END) AS geom
FROM (
  SELECT {{line.name}},{{line.tags}},{{line.waterway_v}} AS class,
    (CASE
      WHEN {{line.bridge_v}} IS NOT NULL AND {{line.bridge_v}}!='no' THEN 'bridge'
      WHEN {{line.tunnel_v}} IS NOT NULL AND {{line.tunnel_v}}!='no' THEN 'tunnel'
    END) AS brunnel,
    (CASE
      WHEN {{line.intermittent_v}} IN ('yes') THEN 1
      ELSE 0
    END) AS intermittent,{{line.way}}
  FROM {{line.table_name}}
  WHERE ST_Intersects({{line.way_v}},bounds_geom)
    AND {{line.waterway_v}} IN ('stream','river','canal','drain','ditch')) AS foo
WHERE
    (z>=13)
    OR (z<13 AND z>=12 AND class IN ('river','canal'))
    OR (z<12 AND z>=11 AND class IN ('river'))
    OR (z<11 AND z>=07 AND name IS NOT NULL AND class IN ('river'))
    --cutoff at z07
GROUP BY(name,class,CASE WHEN z<=10 THEN NULL ELSE brunnel END,intermittent);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_place(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_place
AS $$
WITH place_toomuch_cities AS (
  SELECT
{% if place_with_osm_id %} (CASE
      WHEN tablefrom='point' THEN 'n'||osm_id
      WHEN tablefrom='polygon' AND osm_id<0 THEN 'r'||(-osm_id)
      WHEN tablefrom='polygon' AND osm_id>0 THEN'w'||osm_id
    END) AS osm_id, {% endif %}
    name,{{name_columns_run}}
    (CASE
      WHEN capital_score=1 THEN 2
      WHEN admin_level=2 THEN 3 -- capitals just above already!
      ELSE admin_level
    END) AS capital,class,iso_a2,
    -- 1e3*1.9^(mlt^1.08)
    ((power(1.9,power({{omt_func_pref}}_get_place_multiplier(class),1.08))::int*1e3)+
      --sqlglot does not like implicit a*b+c*d, instead (a*b)+(c*d)
      (capital_score*3e6)+(province_score*2e6)+coalesce(population,0)) AS score,
    (CASE WHEN tablefrom='point' THEN way
      WHEN tablefrom='polygon' THEN ST_PointOnSurface(way) END) AS way
  FROM (
    SELECT
{% if place_with_osm_id %} {{polygon.osm_id}}, {% endif %}
      {{polygon.tags}},
      {{polygon.name}},{{polygon.place_v}} AS class,
      COALESCE({{polygon.iso3166_1_alpha2_v}},{{polygon.iso3166_1_v}},
        {{polygon.country_code_fips_v}},{{polygon.country_code_iso3166_1_alpha_2_v}}) AS iso_a2,
      {{polygon.way}},
      -- 1 if place is a capital
      coalesce({{polygon.capital_ctv}}='yes',false)::int AS capital_score,
      -- 1 if place is a province capital
      coalesce({{polygon.admin_centre_4_v}}='yes',({{polygon.admin_level_v}}::int<=4),
        false)::int AS province_score,
      {{polygon.admin_level_v}}::int AS admin_level,
      {{omt_func_pref}}_text_to_int_null({{polygon.population_ctv}}) AS population,'polygon' AS tablefrom
    FROM {{polygon.table_name}}
    WHERE {{polygon.place_v}} IN ('island')
    UNION ALL
    SELECT
{% if place_with_osm_id %} {{point.osm_id}}, {% endif %}
      {{point.tags}},
      {{point.name}},{{point.place_v}} AS class,
      COALESCE({{point.iso3166_1_alpha2_v}},{{point.iso3166_1_v}},
        {{point.country_code_fips_v}},{{point.country_code_iso3166_1_alpha_2_v}}) AS iso_a2,
      {{point.way}},
      coalesce({{point.capital_ctv}}='yes',false)::int AS capital_score,
      --coalesce({{point.capital_ctv}}='yes',({{point.admin_level_v}}::int<=2),false)::int AS capital_score,
      coalesce({{point.admin_centre_4_v}}='yes',({{point.admin_level_v}}::int<=4),false)::int AS province_score,
      {{point.admin_level_v}}::int AS admin_level,
      {{omt_func_pref}}_text_to_int_null({{point.population_ctv}}) AS population,'point' AS tablefrom
    FROM {{point.table_name}}
    WHERE {{point.place_v}} IN ('continent','country','state','province','city','town','village',
      'hamlet','suburb','quarter','neighbourhood','isolated_dwelling','island')
    ) AS layer_place
    WHERE ST_Intersects(way,bounds_geom) AND ((z>=12)
      OR (z>=10 AND z<12 AND {{omt_func_pref}}_get_place_multiplier(class)>3)
      OR (z>=07 AND z<10 AND {{omt_func_pref}}_get_place_multiplier(class)>6)
      OR (z>=04 AND z<07 AND {{omt_func_pref}}_get_place_multiplier(class)>6) -- city+town include all, other filtering mechanism below...
      OR (z>=03 AND z<04 AND {{omt_func_pref}}_get_place_multiplier(class)>9)
      --only countries or continents
      OR ({{omt_func_pref}}_get_place_multiplier(class)>10))
), place_nocities AS (
  SELECT * FROM place_toomuch_cities WHERE class NOT IN ('city','town')
), place_onlycities AS (
  SELECT * FROM place_toomuch_cities WHERE class IN ('city','town'))
SELECT
{% if place_with_osm_id %} osm_id, {% endif %}
    name, {{name_columns_subquery_propagate}} capital,class,iso_a2,
    -- add rank only at the end...
    (ntile(9) OVER (ORDER BY score DESC))::int+1 AS rank,geom
FROM (
  SELECT
{% if place_with_osm_id %} osm_id, {% endif %}
    name, {{name_columns_subquery_propagate}} capital,class,iso_a2,
    score,ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
  FROM place_nocities
  UNION (
-- some cities are big enough to be shown above provinces. but weed out the small ones
  SELECT
{% if place_with_osm_id %} osm_id, {% endif %}
    name, {{name_columns_subquery_propagate}} capital,class,iso_a2,
    score,ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
  FROM place_onlycities ORDER BY score DESC
  LIMIT (CASE WHEN (z>10) THEN 99999999
    WHEN (z=10) THEN 250
    WHEN (z=09) THEN 200
    WHEN (z=08) THEN 160
    WHEN (z=07) THEN 120
    WHEN (z<=06) THEN 80 END)
  )
) AS filtered_cities_without_rank;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_poi_class_subclass_rank(class text,subclass text)
    RETURNS int AS
$$
SELECT CASE class
           WHEN 'hospital' THEN CASE subclass
              WHEN 'hospital' THEN 15
              ELSE 20 END
           WHEN 'railway' THEN CASE subclass
              WHEN 'station' THEN 30
              ELSE 40 END
           WHEN 'bus' THEN 50
           WHEN 'attraction' THEN CASE subclass
              WHEN 'viewpoint' THEN 60
              ELSE 70 END
           WHEN 'harbor' THEN 75
           WHEN 'college' THEN 80
           WHEN 'school' THEN 85
           WHEN 'stadium' THEN 90
           WHEN 'zoo' THEN 95
           WHEN 'town_hall' THEN 100
           WHEN 'townhall' THEN 100
           WHEN 'campsite' THEN 110
           WHEN 'cemetery' THEN 115
           WHEN 'park' THEN 120
           WHEN 'library' THEN 130
           WHEN 'police' THEN 135
           WHEN 'post' THEN 140
           WHEN 'golf' THEN 150
           WHEN 'shop' THEN 400
           WHEN 'grocery' THEN 500
           WHEN 'fast_food' THEN 600
           WHEN 'clothing_store' THEN 700
           WHEN 'bar' THEN 800
           ELSE 1000
           END;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_poi_pre_rank(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_poi
AS $$
-- additional source:
-- https://wiki.openstreetmap.org/wiki/OpenStreetMap_Carto/Symbols#Shops_and_services
SELECT
{% if poi_with_osm_id %} osm_id, {% endif %}
  name,{{name_columns_subquery_propagate}} class,subclass,
  -- WARNING: not the final rank value, intermediary result only
  (row_number() OVER (ORDER BY ((CASE
    WHEN name IS NOT NULL THEN -100 ELSE 0
  END)+{{omt_func_pref}}_get_poi_class_subclass_rank(class,subclass)) ASC,
    score ASC NULLS LAST,
    start_date_year ASC NULLS LAST
    ))::int AS rank,
  agg_stop,{{omt_func_pref}}_text_to_int_null(level) AS level,layer,indoor,geom
FROM
(SELECT name,
  {{name_columns_subquery_propagate}}
{% if poi_with_osm_id %} osm_id, {% endif %}
	(CASE WHEN
		subclass IN ('accessories','antiques','beauty','bed','boutique','camera',
			'carpet','charity','chemist','coffee','computer','convenience','copyshop',
			'cosmetics','garden_centre','doityourself','erotic','electronics','fabric',
			'florist','frozen_food','furniture','video_games','video','general','gift',
			'hardware','hearing_aids','hifi','ice_cream','interior_decoration',
			'jewelry','kiosk','locksmith','lamps','mall','massage','motorcycle',
			'mobile_phone','newsagent','optician','outdoor','paint','perfumery',
			'perfume','pet','photo','second_hand','shoes','sports','stationery',
			'tailor','tattoo','ticket','tobacco','toys','travel_agency','watches',
			'weapons','wholesale', --added later
      'farm','jewellery','pastry','trade'
    ) THEN 'shop'
    WHEN subclass IN ('townhall','town_hall', 'public_building', 'courthouse',
      'community_centre') THEN 'town_hall'
    WHEN subclass IN ('golf', 'golf_course', 'miniature_golf') THEN 'golf'
		WHEN subclass IN ('fast_food', 'food_court') THEN 'fast_food'
		WHEN subclass IN ('park', 'bbq') THEN 'park'
		WHEN subclass IN ('bus_stop', 'bus_station') THEN 'bus'
		WHEN subclass IN ('halt', 'tram_stop', 'subway') THEN 'railway'
		WHEN subclass IN ('station') THEN subclass_helper_key -- either 'railway' OR 'aerialway'
		WHEN subclass IN ('subway_entrance', 'train_station_entrance') THEN 'entrance'
		WHEN subclass IN ('camp_site', 'caravan_site') THEN 'campsite'
		WHEN subclass IN ('laundry', 'dry_cleaning') THEN 'laundry'
		WHEN subclass IN ('supermarket', 'deli', 'delicatessen', 'department_store',
      'greengrocer', 'marketplace') THEN 'grocery'
		WHEN subclass IN ('university', 'college') THEN 'college'
		WHEN subclass IN ('hotel', 'motel', 'bed_and_breakfast', 'guest_house', 'hostel',
      'chalet', 'alpine_hut', 'dormitory') THEN 'lodging'
		WHEN subclass IN ('chocolate', 'confectionery') THEN 'ice_cream'
		WHEN subclass IN ('post_box', 'post_office', 'parcel_locker') THEN 'post'
		WHEN subclass IN ('cafe') THEN 'cafe'
		WHEN subclass IN ('school', 'kindergarten') THEN 'school'
		WHEN subclass IN ('alcohol', 'beverages', 'wine') THEN 'alcohol_shop'
		WHEN subclass IN ('bar', 'nightclub') THEN 'bar'
		WHEN subclass IN ('marina', 'dock') THEN 'harbor'
		WHEN subclass IN ('car', 'car_repair', 'car_parts', 'taxi') THEN 'car'
		WHEN subclass IN ('hospital', 'nursing_home', 'clinic') THEN 'hospital'
		WHEN subclass IN ('grave_yard', 'cemetery') THEN 'cemetery'
		WHEN subclass IN ('attraction', 'viewpoint') THEN 'attraction'
      --EXTENSION
    WHEN (regexp_match(subclass,'^[a-zA-Z0-9]+'))[1] IN ('tower') THEN 'attraction'
		WHEN subclass IN ('biergarten', 'pub') THEN 'beer'
		WHEN subclass IN ('music', 'musical_instrument') THEN 'music'
		WHEN subclass IN ('american_football', 'stadium', 'soccer') THEN 'stadium'
		WHEN subclass IN ('art', 'artwork', 'gallery', 'arts_centre') THEN 'art_gallery'
		WHEN subclass IN ('bag', 'clothes') THEN 'clothing_store'
		WHEN subclass IN ('swimming_area', 'swimming') THEN 'swimming'
		WHEN subclass IN ('castle', 'ruins') THEN 'castle'
		WHEN subclass IN ('atm') THEN 'atm'	
    ELSE subclass
	END) AS class,
  --rewrite subclass
	(CASE
    WHEN subclass IN ('attraction')
      -- take only starting alphanumeric chars: stop at first '_'
      -- eg 'cave_entrance' -> 'cave'
      THEN (regexp_match(COALESCE(amenity,"natural",man_made,'photo'),E'^[a-zA-Z0-9]+'))[1]
    WHEN subclass IN ('information')
      THEN information
    WHEN subclass='fire_station' THEN 'firestation'
    ELSE subclass
  END) AS subclass,
  agg_stop,level,layer,indoor,score,start_date_year,
  geom
	FROM (SELECT name,
    {{name_columns_run}}
{% if poi_with_osm_id %} osm_id, {% endif %}
		(CASE WHEN
		waterway IN ('dock')
			THEN waterway
    WHEN building IN ('dormitory')
			THEN building
    WHEN shop IN ('accessories','alcohol','antiques','art','bag','bakery','beauty',
			'bed','beverages','bicycle','books','boutique','butcher','camera','car',
			'car_repair','car_parts','carpet','charity','chemist','chocolate',
			'clothes','coffee','computer','confectionery','convenience','copyshop',
			'cosmetics','deli','delicatessen','department_store','doityourself',
			'dry_cleaning','electronics','erotic','fabric','florist','frozen_food',
			'furniture','garden_centre','general','gift','greengrocer','hairdresser',
			'hardware','hearing_aids','hifi','ice_cream','interior_decoration',
			'jewelry','kiosk','lamps','laundry','locksmith','mall','massage',
			'mobile_phone','motorcycle','music','musical_instrument','newsagent',
			'optician','outdoor','paint','perfume','perfumery','pet','photo',
			'second_hand','shoes','sports','stationery','supermarket','tailor',
			'tattoo','ticket','tobacco','toys','travel_agency','video','video_games',
			'watches','weapons','wholesale','wine')
			THEN shop
    --added later from openstreetmap wiki/symbols tab
    WHEN shop IN ('farm') THEN 'greengrocer'
    WHEN shop IN ('jewellery') THEN 'jewelry'
    WHEN shop IN ('pastry') THEN 'confectionery'
    WHEN shop IN ('trade') THEN 'wholesale'
    WHEN shop IN ('fashion') THEN 'clothes'
    WHEN highway IN ('bus_stop') THEN highway
    WHEN leisure IN ('dog_park','escape_game','garden','golf_course','ice_rink',
			'hackerspace','marina','miniature_golf','park','pitch','playground',
			'sports_centre','stadium','swimming_area','swimming_pool','water_park')
			THEN leisure
		WHEN historic IN ('monument','castle','ruins') THEN historic
		WHEN railway IN ('halt','station','subway_entrance','train_station_entrance',
			'tram_stop') THEN railway
		WHEN sport IN ('american_football','archery','athletics','australian_football',
			'badminton','baseball','basketball','beachvolleyball','billiards','bmx',
			'boules','bowls','boxing','canadian_football','canoe','chess','climbing',
			'climbing_adventure','cricket','cricket_nets','croquet','curling','cycling',
			'disc_golf','diving','dog_racing','equestrian','fatsal','field_hockey',
			'free_flying','gaelic_games','golf','gymnastics','handball','hockey',
			'horse_racing','horseshoes','ice_hockey','ice_stock','judo','karting',
			'korfball','long_jump','model_aerodrome','motocross','motor','multi',
			'netball','orienteering','paddle_tennis','paintball','paragliding','pelota',
			'racquet','rc_car','rowing','rugby','rugby_league','rugby_union','running',
			'sailing','scuba_diving','shooting','shooting_range','skateboard','skating',
			'skiing','soccer','surfing','swimming','table_soccer','table_tennis',
			'team_handball','tennis','toboggan','volleyball','water_ski','yoga')
			THEN sport
		WHEN office IN ('diplomatic') THEN office
		WHEN landuse IN ('basin','brownfield','cemetery','reservoir','winter_sports')
			THEN landuse
    WHEN (regexp_match(man_made,'^[a-zA-Z0-9]+'))[1] IN ('tower') THEN man_made
		WHEN tourism IN ('alpine_hut','aquarium','artwork','attraction',
			'bed_and_breakfast','camp_site','caravan_site','chalet','gallery',
			'guest_house','hostel','hotel','information','motel','museum','picnic_site',
			'theme_park','viewpoint','zoo')
			THEN tourism
		WHEN barrier IN ('bollard','border_control','cycle_barrier','gate','lift_gate',
			'sally_port','stile','toll_booth')
			THEN barrier
		WHEN amenity IN ('arts_centre','atm','bank','bar','bbq','bicycle_parking',
			'bicycle_rental','biergarten','bus_station','cafe','cinema','clinic','college',
			'community_centre','courthouse','dentist','doctors','drinking_water','fast_food',
			'ferry_terminal','fire_station','food_court','fuel','grave_yard','hospital',
			'ice_cream','kindergarten','library','marketplace','motorcycle_parking',
			'nightclub','nursing_home','parking','pharmacy','place_of_worship','police',
			'parcel_locker','post_box','post_office','prison','pub','public_building',
			'recycling','restaurant','school','shelter','swimming_pool','taxi','telephone',
			'theatre','toilets','town_hall','university','veterinary','waste_basket')
			THEN amenity
    WHEN amenity='townhall' THEN 'town_hall'
		WHEN aerialway IN ('station') THEN aerialway
		END) AS subclass,
		(CASE WHEN
			railway IN ('station') THEN 'railway'
			WHEN aerialway IN ('station') THEN 'aerialway'
		END) AS subclass_helper_key, -- distinguish railway=station and aerialway=station
		NULL::int AS agg_stop, -- TODO: not implemented
		level AS level,layer,
		(CASE WHEN indoor IN ('yes','1') THEN 1 END) AS indoor,
    amenity,"natural",
    -- EXTENSION/IMPROVEMENTs : start_date_year for score ordering,
    --  man_made for class~tourism,attraction and rewriting subclass
    -- natural in quotes because it's also a numbertype: to not trip up postgres
    man_made,
    start_date_year,score,information,
    ST_AsMVTGeom((CASE WHEN tablefrom='point' THEN way
      WHEN tablefrom='polygon' THEN ST_PointOnSurface(way) END),bounds_geom {{bounds_geom_options}}) AS geom
	FROM (
    SELECT
{% if poi_with_osm_id %} 'n'||{{point.osm_id_v}} AS osm_id, {% endif %}
      {{point.tags}}, -- for name languages
      {{point.name}},{{point.waterway}},{{point.building}},{{point.shop}},
      {{point.highway}},{{point.leisure}},{{point.historic}},
      {{point.railway}},{{point.sport}},{{point.office}},{{point.tourism}},
      {{point.landuse}},{{point.barrier}},{{point.amenity}},{{point.aerialway}},
      {{point.level}},{{point.indoor}},{{point.layer}},{{point.natural}},
      ({{point.wikipedia_ne}}::int+{{point.wikidata_ne}}::int) AS score,
      -- EXTENSION
      ({{point.man_made_v}}||COALESCE('_'||{{point.tower_type_v}},'')) AS man_made,
      {{omt_func_pref}}_get_start_date_year({{point.start_date_v}}) AS start_date_year,
      -- MORE SPECIFIC
      {{point.information}},
      {{point.way}},'point' AS tablefrom
    FROM {{point.table_name}}
    UNION ALL
    SELECT
{% if poi_with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
{% endif %}
      {{polygon.tags}}, -- for name languages
      {{polygon.name}},{{polygon.waterway}},{{polygon.building}},{{polygon.shop}},
      {{polygon.highway}},{{polygon.leisure}},{{polygon.historic}},
      {{polygon.railway}},{{polygon.sport}},{{polygon.office}},{{polygon.tourism}},
      {{polygon.landuse}},{{polygon.barrier}},{{polygon.amenity}},{{polygon.aerialway}},
      {{polygon.level}},{{polygon.indoor}},{{polygon.layer}},{{polygon.natural}},
      ({{polygon.wikipedia_ne}}::int+{{polygon.wikidata_ne}}::int) AS score,
      -- EXTENSION
      ({{polygon.man_made_v}}||COALESCE('_'||{{polygon.tower_type_v}},'')) AS man_made,
      {{omt_func_pref}}_get_start_date_year({{polygon.start_date_v}}) AS start_date_year,
      -- MORE SPECIFIC
      {{polygon.information}},
      {{polygon.way}},'polygon' AS tablefrom
    FROM {{polygon.table_name}}
    ) AS layer_poi
	WHERE (
		waterway IN ('dock')
		OR building IN ('dormitory')
		OR shop IN ('accessories','alcohol','antiques','art','bag','bakery','beauty',
			'bed','beverages','bicycle','books','boutique','butcher','camera','car',
			'car_repair','car_parts','carpet','charity','chemist','chocolate',
			'clothes','coffee','computer','confectionery','convenience','copyshop',
			'cosmetics','deli','delicatessen','department_store','doityourself',
			'dry_cleaning','electronics','erotic','fabric','florist','frozen_food',
			'furniture','garden_centre','general','gift','greengrocer','hairdresser',
			'hardware','hearing_aids','hifi','ice_cream','interior_decoration',
			'jewelry','kiosk','lamps','laundry','locksmith','mall','massage',
			'mobile_phone','motorcycle','music','musical_instrument','newsagent',
			'optician','outdoor','paint','perfume','perfumery','pet','photo',
			'second_hand','shoes','sports','stationery','supermarket','tailor',
			'tattoo','ticket','tobacco','toys','travel_agency','video','video_games',
			'watches','weapons','wholesale','wine', -- added later on:
      'farm','jewellery','pastry','trade','fashion'
      )
		OR highway IN ('bus_stop')
		OR leisure IN ('dog_park','escape_game','garden','golf_course','ice_rink',
			'hackerspace','marina','miniature_golf','park','pitch','playground',
			'sports_centre','stadium','swimming_area','swimming_pool','water_park')
		OR historic IN ('monument','castle','ruins')
		OR railway IN ('halt','station','subway_entrance','train_station_entrance',
			'tram_stop')
		OR sport IN ('american_football','archery','athletics','australian_football',
			'badminton','baseball','basketball','beachvolleyball','billiards','bmx',
			'boules','bowls','boxing','canadian_football','canoe','chess','climbing',
			'climbing_adventure','cricket','cricket_nets','croquet','curling','cycling',
			'disc_golf','diving','dog_racing','equestrian','fatsal','field_hockey',
			'free_flying','gaelic_games','golf','gymnastics','handball','hockey',
			'horse_racing','horseshoes','ice_hockey','ice_stock','judo','karting',
			'korfball','long_jump','model_aerodrome','motocross','motor','multi',
			'netball','orienteering','paddle_tennis','paintball','paragliding','pelota',
			'racquet','rc_car','rowing','rugby','rugby_league','rugby_union','running',
			'sailing','scuba_diving','shooting','shooting_range','skateboard','skating',
			'skiing','soccer','surfing','swimming','table_soccer','table_tennis',
			'team_handball','tennis','toboggan','volleyball','water_ski','yoga')
		OR office IN ('diplomatic')
		OR landuse IN ('basin','brownfield','cemetery','reservoir','winter_sports')
		OR tourism IN ('alpine_hut','aquarium','artwork','attraction',
			'bed_and_breakfast','camp_site','caravan_site','chalet','gallery',
      -- 'information' :
			'guest_house','hostel','hotel','information','motel','museum','picnic_site',
			'theme_park','viewpoint','zoo')
		OR barrier IN ('bollard','border_control','cycle_barrier','gate','lift_gate',
			'sally_port','stile','toll_booth')
		OR amenity IN ('arts_centre','atm','bank','bar','bbq','bicycle_parking',
			'bicycle_rental','biergarten','bus_station','cafe','cinema','clinic','college',
			'community_centre','courthouse','dentist','doctors','drinking_water','fast_food',
			'ferry_terminal','fire_station','food_court','fuel','grave_yard','hospital',
			'ice_cream','kindergarten','library','marketplace','motorcycle_parking',
			'nightclub','nursing_home','parking','pharmacy','place_of_worship','police',
			'parcel_locker','post_box','post_office','prison','pub','public_building',
			'recycling','restaurant','school','shelter','swimming_pool','taxi','telephone',
			'theatre','toilets','townhall','town_hall','university','veterinary','waste_basket')
		OR aerialway IN ('station')
    OR man_made IN ('tower')
		) AND ST_Intersects(way,bounds_geom)) AS without_rank_without_class
) AS without_rank
WHERE (z>=14)
  OR (z<14 AND z>=13 AND class IN ('hospital','railway','bus','attraction','college'))
  OR (z<13 AND z>=12 AND (class IN ('hospital','bus','attraction')
        OR (class='railway' AND subclass='station')))
  OR (z<12 AND z>=10 AND (class='railway' AND subclass='station'));
  -- and zoom cutoff here is z10
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_poi(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_poi
AS $$
-- The rank copmutation and documentation are very unclear and how they are now could be better
SELECT
{% if poi_with_osm_id %} osm_id, {% endif %}
  name,{{name_columns_subquery_propagate}} class,subclass,
{% if same_rank_poi_high_zooms %} (CASE WHEN z>=15 THEN 30::int ELSE {%endif%}
  (row_number() OVER (ORDER BY rank ASC))::int
{% if same_rank_poi_high_zooms %} END) {%endif%} AS rank,
  agg_stop,level,layer,indoor,geom
FROM (
  SELECT
{% if poi_with_osm_id %} osm_id, {% endif %}
    name,{{name_columns_subquery_propagate}} class,subclass,rank,
    (row_number() OVER (PARTITION BY(class)
      ORDER BY rank ASC)) AS inclass_rank,
    agg_stop,level,layer,indoor,geom
  FROM {{omt_func_pref}}_poi_pre_rank(bounds_geom,z)) AS without_global_rank
WHERE inclass_rank<=30 OR z>=14;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_pre_agg_water_merged(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_water_merged
AS $$
SELECT
-- include osm_id for get_lakeline lookup
  osm_id,name, {{name_columns_run}} class,intermittent,brunnel,way,tablefrom
FROM (
  SELECT
    {{polygon.osm_id}},{{polygon.name}},{{polygon.tags}},
    (CASE
      WHEN {{polygon.water_v}} IN ('river','lake','ocean') THEN {{polygon.water_v}}
      WHEN {{polygon.waterway_v}} IN ('dock') THEN 'dock'
      WHEN {{polygon.leisure_v}} IN ('swimming_pool') THEN 'swimming_pool'
      ELSE 'lake'
    END) AS class,
    (CASE
      WHEN {{polygon.intermittent_v}} IN ('yes') THEN 1
      ELSE 0
    END) AS intermittent,
    (CASE
      WHEN {{polygon.bridge_v}} IS NOT NULL AND {{polygon.bridge_v}}!='no' THEN 'bridge'
      WHEN {{polygon.tunnel_v}} IS NOT NULL AND {{polygon.tunnel_v}}!='no' THEN 'tunnel'
    END) AS brunnel,
    {{polygon.way}}, 'polygon' AS tablefrom
  FROM {{polygon.table_name}}
  WHERE ({{polygon.covered_v}} IS NULL OR {{polygon.covered_v}} != 'yes') AND (
      {{polygon.water_v}} IN ('river','lake') OR {{polygon.waterway_v}} IN ('dock')
      OR {{polygon.natural_v}} IN ('water','bay','spring') OR {{polygon.leisure_v}} IN ('swimming_pool')
      OR {{polygon.landuse_v}} IN ('reservoir','basin','salt_pond'))
    AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
      (z>=13) OR
      (z=12 AND {{polygon.way_area_v}}>1500) OR
      (z=11 AND {{polygon.way_area_v}}>6000) OR
      (z=10 AND {{polygon.way_area_v}}>24e3) OR
      (z=09 AND {{polygon.way_area_v}}>96e3) OR
      (z=08 AND {{polygon.way_area_v}}>384e3) OR
      (z=07 AND {{polygon.way_area_v}}>1536e3) OR
      (z=06 AND {{polygon.way_area_v}}>6e6) OR
      -- show lake-like polygons only (rivers are not way_area big enough;
      --  and also too small to see at that point)
      -- polar regions! srid=8857 is area-preserving and area_8857~=area_3857 at EQUATOR ONLY
      -- for performance: check way_area a tenth smaller too
      (z=05 AND {{polygon.way_area_v}}>1e6 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>12e6) OR
      (z=04 AND {{polygon.way_area_v}}>2e6 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>20e6) OR
      (z=03 AND {{polygon.way_area_v}}>4e6 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>40e6) OR
      (z=02 AND {{polygon.way_area_v}}>5e6 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>50e6) OR
      (z<=01 AND {{polygon.way_area_v}}>10e6 AND ST_Area(ST_Transform({{polygon.way_v}},8857))>100e6)
    )
  UNION
  SELECT
    {{point.osm_id}},
    -- pacific ocean and others have a name IS NULL because some kind of noname=multiple_languages.
    -- take name:en as default (and other langs included as usual)
    COALESCE({{point.name_v}},{{point.name_en_v}}) AS name,{{point.tags}},
    (CASE
      WHEN {{point.place_v}} IN ('sea','ocean') THEN {{point.place_v}}
      WHEN {{point.natural_v}} IN ('bay','strait') THEN {{point.natural_v}}
    END) AS class,
    0 AS intermittent,
    NULL AS brunnel,
    {{point.way}}, 'point' AS tablefrom
  FROM {{point.table_name}}
  WHERE ({{point.place_v}} IN ('sea','ocean')
      OR {{point.natural_v}} IN ('bay','strait'))
    AND ST_Intersects({{point.way_v}},bounds_geom)
  ) AS foo;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_water_name(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_water_name
AS $$
SELECT
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
  name, {{name_columns_subquery_propagate}} class,intermittent,
  -- openmaptiles uses https://github.com/openmaptiles/osm-lakelines basically a docker wrapper,
  -- of https://github.com/ungarj/label_centerlines/blob/master/label_centerlines/_src.py
  ST_AsMVTGeom(
    CASE WHEN tablefrom!='point' THEN
    {{omt_func_pref}}_get_lakeline(way,osm_id)
    ELSE way END,
    bounds_geom {{bounds_geom_options}}) AS geom
FROM {{omt_func_pref}}_pre_agg_water_merged(bounds_geom,z)
WHERE class IN ('ocean','lake','sea') AND (name IS NOT NULL OR {{name_columns_any_notnull}}) AND (
      (tablefrom='point' AND (z>=03
          -- only ocean points at z00-z02
          OR class IN ('ocean'))
      ) OR
      (z>=06)
      OR (z=05 AND ST_Area(ST_Transform(way,8857))>400e6)
      OR (z=04 AND ST_Area(ST_Transform(way,8857))>800e6)
      OR (z=03 AND ST_Area(ST_Transform(way,8857))>1.6e7)
      OR (z=02 AND ST_Area(ST_Transform(way,8857))>3e7));
    -- no polygon water names below z02
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_post_agg_water(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_water
AS $$
SELECT
{% if with_osm_id %}
    --LIMIT 5 but that's a syntax error in an aggregate
    array_to_string((array_agg(DISTINCT osm_id ORDER BY osm_id ASC))[1:5],',') AS osm_id,
{% endif %}
  class,intermittent,brunnel,
  ST_Simplify(
    ST_AsMVTGeom(ST_UnaryUnion(unnest(ST_ClusterIntersecting(way))),bounds_geom {{bounds_geom_options}}),
    -- at z04~z07, some water polygons sometimes make horrible triangles
    --  (always pointing to the right somehow), and the ST_SimplifyPreserveTopology
    -- threshold can make them go away. But setting it too low means more data.
    -- please report issues if these settings still make bad water triangles.
    -- sample tiles: 7/110/51 ocean polygons, 6/35/23 and 6/36/23 river Danube
    --  4/0/4 ocean polygons
    CASE WHEN z>=5 THEN 3
    WHEN z<=4 THEN 1 END) AS geom
FROM {{omt_func_pref}}_pre_agg_water_merged(bounds_geom,z)
WHERE tablefrom!='point' -- only relevant for water_name layer
GROUP BY (class,intermittent,brunnel);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


{% macro query_osmdata_water() %}
SELECT * FROM {{omt_func_pref}}_post_agg_water(bounds_geom,z)
{% endmacro %}
{% macro query_naturalearth_ocean(tbl_name) %}
SELECT
{% if with_osm_id %} 'ne_fid'||(ogc_fid::text) AS osm_id, {% endif %}
  'ocean' AS class,0 AS intermittent,NULL AS brunnel,
  ST_AsMVTGeom(way,bounds_geom {{bounds_geom_options}}) AS geom
  FROM {{tbl_name}}
  WHERE ST_Intersects(way,bounds_geom)
{% endmacro %}
{% macro query_water_polygons() %}
SELECT
{% if with_osm_id %} 'wt_polygs' AS osm_id, {% endif %}
  'ocean' AS class,0 AS intermittent,
  -- the _post_agg_water has already simplified
  NULL AS brunnel,ST_SimplifyPreserveTopology(
    ST_AsMVTGeom(ST_UnaryUnion(unnest(ST_ClusterIntersecting(way))),bounds_geom {{bounds_geom_options}}),
    10) AS geom
FROM water_polygons WHERE ST_Intersects(way,bounds_geom) AND z>=07
{% endmacro %}

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_water(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_water
AS $$
BEGIN
  IF z>=07 THEN
    RETURN QUERY
      {{query_osmdata_water()}} UNION
      {{query_water_polygons()}};
  ELSIF z>=05 AND z<=06 THEN
    RETURN QUERY
      {{query_osmdata_water()}} UNION
      {{query_naturalearth_ocean('ne_10m_ocean')}};
  ELSIF z>=02 AND z<=04 THEN
    RETURN QUERY
      {{query_osmdata_water()}} UNION
      {{query_naturalearth_ocean('ne_50m_ocean')}};
  ELSE
    RETURN QUERY
      {{query_osmdata_water()}} UNION
      {{query_naturalearth_ocean('ne_110m_ocean')}};
  END IF;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_collect_all(z integer, x integer, y integer)
RETURNS table(mvt bytea,name text,rowcount bigint)
AS $$
-- ST_TileEnvelope will be cached:
-- SELECT pg_get_functiondef('st_tileenvelope'::regproc) ~ 'IMMUTABLE';
WITH
  premvt_aerodrome_label AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_aerodrome_label(ST_TileEnvelope(z,x,y),z)),
  premvt_aeroway AS (
    SELECT * FROM {{omt_func_pref}}_aeroway(ST_TileEnvelope(z,x,y),z)),
  premvt_boundary AS (
    SELECT * FROM {{omt_func_pref}}_boundary(ST_TileEnvelope(z,x,y),z)),
  premvt_building AS (
    SELECT * FROM {{omt_func_pref}}_building(ST_TileEnvelope(z,x,y),z)),
  premvt_housenumber AS (
    SELECT * FROM {{omt_func_pref}}_housenumber(ST_TileEnvelope(z,x,y),z)),
  premvt_landcover AS (
    SELECT * FROM {{omt_func_pref}}_landcover(ST_TileEnvelope(z,x,y),z)),
  premvt_landuse AS (
    SELECT * FROM {{omt_func_pref}}_landuse(ST_TileEnvelope(z,x,y),z)),
  premvt_mountain_peak AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_mountain_peak(ST_TileEnvelope(z,x,y),z)),
  premvt_park AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_park(ST_TileEnvelope(z,x,y),z)),
  premvt_place AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_place(ST_TileEnvelope(z,x,y),z)),
  premvt_poi AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_poi(ST_TileEnvelope(z,x,y),z)
    ORDER BY(rank) ASC
  ),
  premvt_waterway AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_waterway(ST_TileEnvelope(z,x,y),z)),
  -- the generated {layer} and {layer}_name:
  premvt_transportation AS (
    SELECT * FROM {{omt_func_pref}}_transportation(ST_TileEnvelope(z,x,y),z)),
  premvt_transportation_name AS (
    SELECT
      {% if with_osm_id %} osm_id, {% endif %}
      {{additional_name_columns}}
      name, {{name_columns_subquery_propagate}}
      replace(ref,';',E'\n') AS ref,length(ref) AS ref_length,
      network,class,subclass,brunnel,level,layer,indoor,
      geom
    FROM {{omt_func_pref}}_transportation_name(ST_TileEnvelope(z,x,y),z)),
  premvt_water AS (
    SELECT * FROM {{omt_func_pref}}_water(ST_TileEnvelope(z,x,y),z)),
  premvt_water_name AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_water_name(ST_TileEnvelope(z,x,y),z))
  SELECT ST_AsMVT(premvt_aerodrome_label,'aerodrome_label') AS mvt,
    'aerodrome_label' AS name,
    count(*) AS rowcount
    FROM premvt_aerodrome_label UNION
  SELECT ST_AsMVT(premvt_aeroway,'aeroway') AS mvt,
    'aeroway' AS name,
    count(*) AS rowcount
    FROM premvt_aeroway UNION
  SELECT ST_AsMVT(premvt_boundary,'boundary') AS mvt,
    'boundary' AS name,
    count(*) AS rowcount
    FROM premvt_boundary UNION
  SELECT ST_AsMVT(premvt_building,'building') AS mvt,
    'building' AS name,
    count(*) AS rowcount
    FROM premvt_building UNION
  SELECT ST_AsMVT(premvt_housenumber,'housenumber') AS mvt,
    'housenumber' AS name,
    count(*) AS rowcount
    FROM premvt_housenumber UNION
  SELECT ST_AsMVT(premvt_landcover,'landcover') AS mvt,
    'landcover' AS name,
    count(*) AS rowcount
    FROM premvt_landcover UNION
  SELECT ST_AsMVT(premvt_landuse,'landuse') AS mvt,
    'landuse' AS name,
    count(*) AS rowcount
    FROM premvt_landuse UNION
  SELECT ST_AsMVT(premvt_mountain_peak,'mountain_peak') AS mvt,
    'mountain_peak' AS name,
    count(*) AS rowcount
    FROM premvt_mountain_peak UNION
  SELECT ST_AsMVT(premvt_park,'park') AS mvt,
    'park' AS name,
    count(*) AS rowcount
    FROM premvt_park UNION
  SELECT ST_AsMVT(premvt_place,'place') AS mvt,
    'place' AS name,
    count(*) AS rowcount
    FROM premvt_place UNION
  SELECT ST_AsMVT(premvt_poi,'poi') AS mvt,
    'poi' AS name,
    count(*) AS rowcount
    FROM premvt_poi UNION
  SELECT ST_AsMVT(premvt_transportation,'transportation') AS mvt,
    'transportation' AS name,
    count(*) AS rowcount
    FROM premvt_transportation UNION
  SELECT ST_AsMVT(premvt_transportation_name,'transportation_name') AS mvt,
    'transportation_name' AS name,
    count(*) AS rowcount
    FROM premvt_transportation_name UNION
  SELECT ST_AsMVT(premvt_water,'water') AS mvt,
    'water' AS name,
    count(*) AS rowcount
    FROM premvt_water UNION
  SELECT ST_AsMVT(premvt_water_name,'water_name') AS mvt,
    'water_name' AS name,
    count(*) AS rowcount
    FROM premvt_water_name UNION
  SELECT ST_AsMVT(premvt_waterway,'waterway') AS mvt,
    'waterway' AS name,
    count(*) AS rowcount
    FROM premvt_waterway;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_all_func}}_with_stats(z integer, x integer, y integer)
RETURNS table(data bytea,pcent numeric,bytes int,pretty_bytes text,name text,rowcount bigint)
AS $$
WITH c AS (
  SELECT mvt,name,rowcount FROM {{omt_func_pref}}_collect_all(z,x,y)),
tot AS (
  SELECT length(string_agg(c.mvt,''::bytea)) AS l,string_agg(c.mvt,''::bytea) AS data FROM c)
SELECT mvt AS data,
  coalesce(round(100*(length(mvt))/nullif(tot.l,0),1),0.0) AS pcent,
  length(mvt) AS bytes,pg_size_pretty(length(mvt)::numeric) AS pretty_bytes,
  name,rowcount
FROM c,tot
UNION
SELECT tot.data AS data,100.0 AS pcent,tot.l AS bytes,
  pg_size_pretty(tot.l::numeric) AS pretty_bytes,
  'ALL' AS name,-1 AS rowcount
FROM tot
ORDER BY(bytes) DESC;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_all_func}}_single_layer(z integer, x integer, y integer,
  filter_name text)
RETURNS bytea
AS $$
SELECT f.mvt FROM {{omt_func_pref}}_collect_all(z,x,y) AS f WHERE f.name=filter_name LIMIT 1;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_all_func}}(z integer, x integer, y integer)
RETURNS bytea
AS $$
SELECT string_agg(mvt,''::bytea) FROM {{omt_func_pref}}_collect_all(z,x,y);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



SELECT pcent,bytes,pretty_bytes,name,rowcount FROM {{omt_all_func}}_with_stats({{test_z}},{{test_x}},{{test_y}});

