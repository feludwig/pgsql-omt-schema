
-- TEMPLATE usage:
-- need to define variables in run.py, then
-- SYNTAX {% if debug %} THEN SQL STATEMENT {% else %} ELSE SQL STATEMENT {% endif %}
--    where debug is a boolean variable
-- other SYNTAX {{ omt_func_pref }}
--    where omt_func_pref is a text variable

-- VARIABLES available :
--  {point} the table storing all point features, default osm2pgsql name planet_osm_point
--    -> {point.table_name} in a FROM {},
--    -> {point.<column_name>} in a SELECT foo, {} FROM ...
--        this becomes "(tags->'col') AS col" when col was not detected in db, and "col" otherwise
--    -> {point.<column_name>_v} in a SELECT ({}+1) AS computed_value [v for "value"]
--        this becomes "(tags->'col')" when col was not detected, and "col" otherwise
--  {line} the table storing all line features, default osm2pgsql name planet_osm_line
--    -> exaclty like {point}, there is a {line.table_name} and
--    -> {line.<column_name>} and {line.<column_name>_v}
--  {polygon} the table storing all line features, default osm2pgsql name planet_osm_polygon
--    -> exaclty like {point}, there is a {polygon.table_name} and
--    -> {polygon.<column_name>} and {polygon.<column_name>_v}
--  ALSO: any column name {point.<colname>_ne} ["not exists"] is a shorthand for
--    ({point.<colname>_v} is null), which gets contracted to "tags"?<colname> in case of tags


-- TODO: 
--  *move all table names to templated table names
--  *after moved all column names to template, check 5432 database as well

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

-- united types to make {layer} and {layer}_name
DROP TYPE IF EXISTS {{omt_typ_pref}}_named_transportation CASCADE;
DROP TYPE IF EXISTS {{omt_typ_pref}}_named_water CASCADE;

-- BEWARE! the order of these columns is important.
-- if you exchange two differently-typed columns, postgresql will not be happy,
-- but the danger is when you exchange two same-type columns: postgresql will
-- happily resturn you the wrong results...

CREATE TYPE {{omt_typ_pref}}_named_transportation AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
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
  cycleway int,
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
  class text,
  iata text,
  icao text,
  ele integer,
  -- not to do: ele_ft
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_aeroway AS (
{% if with_osm_id %} osm_id text, {% endif %}
  ref text,
  class text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_boundary AS (
  admin_level integer,
  adm0_l text,
  adm0_r text,
  disputed integer, --TODO: fix, for now always returning 0
  --disputed_name text,
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
  class text,
  subclass text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_landuse AS (
  class text,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_mountain_peak AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  class text,
  ele integer,
  -- not to do: ele_ft, customary_fr
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_park AS (
  name text,
  class text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_place AS (
{% if with_osm_id %} osm_id text, {% endif %}
{% if debug %} way_area real, {% endif %}
  name text,
  capital integer,
  class text,
  iso_a2 text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_poi AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  class text,
  subclass text,
  rank integer,
  agg_stop integer,
  level int,
  layer int,
  indoor int,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_named_water AS (
  name text,
  id bigint,
  class text,
  intermittent integer,
  brunnel text, --TODO: only two-possibility, NOT ford
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_waterway AS (
  name text,
  class text,
  brunnel text, -- TODO: only two-value possible
  intermittent integer,
  geom geometry
);



--utilities
CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_real_0(data text) RETURNS real
AS $$
SELECT CASE
  WHEN data~E'^\\d+(\\.\\d+)?$' THEN data::real
  WHEN data~E'^\\.\\d+$' THEN ('0'||data)::real -- '.9' -> '0.9' -> 0.9
  ELSE 0.0 END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_int_null(data text) RETURNS integer
AS $$
SELECT CASE
  WHEN data~E'^\\d$' THEN data::integer
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_rank_by_area(area real) RETURNS int
AS $$
SELECT CASE WHEN v.val<1 THEN 1 ELSE v.val END
  FROM (SELECT -1*log(20.0,area::numeric)::int+10 AS val) AS v;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_adjust_rank_by_class(class text) RETURNS int
AS $$
SELECT CASE 
  WHEN class IN ('continent','country','state') THEN -2
  WHEN class IN ('province','city') THEN -1
  WHEN class IN ('village') THEN +1
  WHEN class IN ('hamlet','suburb','quarter','neighbourhood') THEN +2
  WHEN class IN ('isolated_dwelling') THEN +3
    -- island, town
  ELSE 0
END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_point_admin_parent_area(node_id bigint) RETURNS real
AS $$
  SELECT way_area FROM (SELECT id
    FROM planet_osm_rels WHERE planet_osm_member_ids(members,'N'::char(1)) && ARRAY[node_id]::bigint[]
    AND (members @> ('[{"type":"N","ref":'||node_id||',"role":"admin_centre"}]')::jsonb
      OR members @> ('[{"type":"N","ref":'||node_id||',"role":"admin_center"}]')::jsonb
      OR members @> ('[{"type":"N","ref":'||node_id||',"role":"label"}]')::jsonb)
  ) AS parents
  JOIN {{polygon.table_name}} ON -parents.id={{polygon.osm_id_v}}
  ORDER BY({{polygon.way_area_v}}) DESC LIMIT 1;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_point_admin_enclosing_rank(node_id bigint) RETURNS int
  -- a neighbourhood is not the admin_centre of anything. instead take its enclosing lowest
  -- admin level. add 1 to the rank to signify smaller than the administrative boundary
  -- BUT if the name is the same for that admin level, take ist rank (+0)
AS $$
WITH enclosing_area AS (
  SELECT {{polygon.way_area}},(SELECT {{point.name}} FROM {{point.table_name}}
      WHERE {{point.osm_id_v}}=node_id)=name AS samename
    FROM {{polygon.table_name}} WHERE {{polygon.boundary_v}}='administrative'
      AND ST_Intersects(way,(SELECT {{point.way}} FROM {{point.table_name}}
          WHERE {{point.osm_id_v}}=node_id))
    ORDER BY({{polygon.admin_level_v}}) DESC LIMIT 1)
  SELECT CASE WHEN enclosing_area.samename=true THEN get_rank_by_area(way_area)
    ELSE
      get_rank_by_area(way_area)+1
    END FROM enclosing_area;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;




CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landuse(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landuse
AS $$
SELECT
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
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom) AS geom
FROM {{polygon.table_name}}
WHERE ({{polygon.landuse_v}} IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail')
  OR {{polygon.leisure_v}} IN ('stadium','pitch','playground','track')
  OR {{polygon.tourism_v}} IN ('theme_park','zoo') OR {{polygon.place_v}} IN ('suburbquarter','neighbourhood')
  OR {{polygon.amenity_v}} IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') OR {{polygon.waterway_v}} IN ('dam')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
    (z>=14 OR {{polygon.way_area_v}}>1500) AND
    (z>=13 OR {{polygon.way_area_v}}>6000) AND
    (z>=12 OR {{polygon.way_area_v}}>24e3) AND
    (z>=11 OR {{polygon.way_area_v}}>96e3) AND
    (z>=10 OR {{polygon.way_area_v}}>384e3) AND
    (z>=09 OR {{polygon.way_area_v}}>1536e3) AND
    (z>=08 OR {{polygon.way_area_v}}>6e6) AND
    (z>=07 OR {{polygon.way_area_v}}>24e6) AND
    (z>=06 OR {{polygon.way_area_v}}>96e6) AND
    (z>=05 OR {{polygon.way_area_v}}>384e6) AND
    (z>=04 OR {{polygon.way_area_v}}>1526e6)
  );
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_aerodrome_label(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_aerodrome_label
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
    name,
    (CASE WHEN aerodrome_type IN ('international','public','regional','miltary','private','other')
      THEN aerodrome_type
      ELSE 'other' -- remove any NULLs
    END) AS class,
    iata,icao,{{omt_func_pref}}_text_to_int_null(ele) AS ele,
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||osm_id) AS osm_id, {% endif %}
    {{point.name}},{{point.aeroway_v}},{{point.aerodrome_type}},
    {{point.iata}},{{point.icao}},{{point.ele}},{{point.way}}
  FROM {{point.table_name}}
  UNION ALL
  SELECT
{% if with_osm_id %}
    (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
    {{polygon.name}},{{polygon.aeroway_v}},{{polygon.aerodrome_type}},
    {{polygon.iata}},{{polygon.icao}},{{polygon.ele}},{{polygon.way}}
  FROM {{polygon.table_name}}
) AS foo
WHERE aeroway='aerodrome' AND ST_Intersects(way,bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_aeroway(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_aeroway
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  ref,class,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||osm_id) AS osm_id, {% endif %}
    {{point.ref}},{{point.aeroway_v}} AS class,{{point.way}}
  FROM {{point.table_name}}
  WHERE {{point.aeroway_v}} IN ('gate')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
    {{line.ref}},{{line.aeroway_v}} AS class,{{line.way}}
  FROM {{line.table_name}}
  WHERE {{line.aeroway_v}} IN ('runway','taxiway')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
    {{polygon.ref}},{{polygon.aeroway_v}} AS class,{{polygon.way}}
  FROM {{polygon.table_name}}
  WHERE {{polygon.aeroway_v}} IN ('aerodrome','heliport','runway','helipad','taxiway','apron')
    ) AS foo
WHERE ST_Intersects({{polygon.way_v}},bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landcover(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landcover
AS $$
SELECT 
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
  ST_AsMVTGeom(way,bounds_geom) AS geom
  FROM (SELECT
    ( CASE
      WHEN landuse IN ('allotments','farm','farmland','orchard','plant_nursery','vineyard',
        'grass','grassland','meadow','forest','village_green','recreation_ground') THEN landuse
      WHEN "natural" IN ('wood','wetland','fell','grassland','heath','scrub','shrubbery','tundra',
      'glacier','bare_rock','scree','beach','sand','dune') THEN "natural"
      WHEN leisure IN ('park','garden','golf_course') THEN leisure
      WHEN tags->'wetland' IN ('bog','swamp','wet_meadow','marsh','reedbed','slatern','tidalflat',
        'saltmarsh','mangrove') THEN tags->'wetland'
      ELSE NULL
    END ) AS subclass,way
  FROM planet_osm_polygon
  WHERE (landuse IN ('allotments','farm','farmland','orchard','plant_nursery','vineyard',
    'grass','grassland','meadow','forest','village_green','recreation_ground')
  OR "natural" IN ('wood','wetland','fell','grassland','heath','scrub','shrubbery','tundra',
    'glacier','bare_rock','scree','beach','sand','dune')
  OR leisure IN ('park','garden','golf_course')
  OR wetland IN ('bog','swamp','wet_meadow','marsh','reedbed','slatern','tidalflat','saltmarsh','mangrove')
  ) AND ST_Intersects(way,bounds_geom) AND (
    (z>=14 OR {{polygon.way_area_v}}>1500) AND
    (z>=13 OR {{polygon.way_area_v}}>6000) AND
    (z>=12 OR {{polygon.way_area_v}}>24e3) AND
    (z>=11 OR {{polygon.way_area_v}}>96e3) AND
    (z>=10 OR {{polygon.way_area_v}}>384e3) AND
    (z>=09 OR {{polygon.way_area_v}}>1536e3) AND
    (z>=08 OR {{polygon.way_area_v}}>6e6) AND
    (z>=07 OR {{polygon.way_area_v}}>24e6) AND
    (z>=06 OR {{polygon.way_area_v}}>96e6) AND
    (z>=05 OR {{polygon.way_area_v}}>384e6) AND
    (z>=04 OR {{polygon.way_area_v}}>1526e6)
  )) AS foo;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION {{omt_func_pref}}_building(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_building
AS $$
SELECT {{omt_func_pref}}_text_to_real_0(tags->'height') AS render_height,
  COALESCE({{omt_func_pref}}_text_to_real_0(tags->'min_height'),
    {{omt_func_pref}}_text_to_real_0(tags->'building:levels')*2.5)::real AS render_min_height,
  --'#ffff00' AS colour,
  (CASE WHEN tags->'building:part' IS NULL THEN false ELSE true END) AS hide_3d,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE building IS NOT NULL AND (tags->'location' != 'underground' OR tags->'location' IS NULL)
   AND ST_Intersects(way,bounds_geom) AND (
    (z>=14 OR way_area>=1700) AND (z>12) -- show no buildings above z>=12
  );
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_park(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_park
AS $$
SELECT name,
  (CASE
    WHEN boundary='aboriginal_lands' THEN boundary
    ELSE COALESCE(replace(lower(NULLIF(tags->'protection_title','')),' ','_'),
      NULLIF(boundary,''),NULLIF(leisure,''))
  END) AS class, z_order AS rank,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE (boundary IN ('national_park','protected_area') OR leisure='nature_reserve')
   AND ST_Intersects(way,bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_mountain_peak(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_mountain_peak
AS $$
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  name,class,{{omt_func_pref}}_text_to_int_null(ele) AS ele,
  (row_number() OVER (ORDER BY ((name IS NULL)::int+score) ASC))::int AS rank,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||osm_id) AS osm_id, {% endif %}
    {{point.name}},{{point.ele}},{{point.way}},
    -- score of 0 means popular item: should be shown first
    ({{point.wikipedia_ne}}::int+{{point.wikidata_ne}}::int) AS score,
    {{point.natural_v}} AS class
  FROM {{point.table_name}}
  WHERE {{point.natural_v}} IN ('peak','volcano','saddle')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
    {{line.name}},{{line.ele}},{{line.way}},
    -- score of 0 means popular item: should be shown first
    ({{line.wikipedia_ne}}::int+{{line.wikidata_ne}}::int) AS score,
    {{line.natural_v}} AS class
  FROM {{line.table_name}}
  WHERE {{line.natural_v}} IN ('ridge','cliff','arete')
    ) AS foo
WHERE ST_Intersects(way,bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_boundary(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_boundary
AS $$
SELECT admin_level::integer AS admin_level,
  tags->'left:country' AS adm0_l,tags->'right:country' AS adm0_r,
  0 AS disputed,
  (CASE admin_level WHEN '2' THEN
    COALESCE(tags->'ISO3166-1:alpha2',tags->'ISO3166-1',tags->'country_code_fips')
    ELSE NULL END) AS claimed_by,
  (CASE boundary WHEN 'maritime' THEN 1 ELSE 0 END) AS maritime,
  ST_AsMVTGeom({{line.way_v}},bounds_geom) AS geom
FROM {{line.table_name}}
WHERE ({{line.boundary_v}} IN ('administrative') OR CASE
    WHEN z<=4 THEN {{line.boundary_v}} IN ('maritime')
      AND {{line.admin_level_v}} IN ('1','2') ELSE false
    END)
   AND (z>=11 OR {{line.admin_level_v}} IN ('1','2','3','4','5','6','7'))
   AND (z>=8 OR {{line.admin_level_v}} IN ('1','2','3','4'))
   AND (z>=2 OR {{line.admin_level_v}} IN ('1','2','3'))
   AND ST_Intersects({{line.way_v}},bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_housenumber(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_housenumber
AS $$
SELECT "addr:housenumber" AS housenumber,
  ST_AsMVTGeom((CASE
      WHEN tablefrom = 'point' THEN way
      ELSE ST_Centroid(way) END),bounds_geom) AS geom
FROM (
  SELECT "addr:housenumber",way,'line' AS tablefrom FROM {{line.table_name}}
  UNION ALL
  SELECT "addr:housenumber",way,'point' AS tablefrom FROM {{point.table_name}}
  UNION ALL
  SELECT "addr:housenumber",way,'polygon' AS tablefrom FROM planet_osm_polygon)
    AS layer_housenumber
  -- obviously don't scan on the ST_Centroid(way) because those are not indexed
WHERE "addr:housenumber" IS NOT NULL AND ST_Intersects(way,bounds_geom)
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_pre_merge_transportation(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
SELECT * FROM (
  SELECT
  {% if with_osm_id %}
    (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
  {% endif %}
    name,
    ref,
  -- from https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
    (CASE
      WHEN highway = 'construction' THEN (CASE
          WHEN construction IN ('motorway','motorway_link') THEN 'motorway_construction'
          WHEN construction IN ('primary','primary_link') THEN 'primary_construction'
          WHEN construction IN ('secondary','secondary_link') THEN 'secondary_construction'
          WHEN construction IN ('tertiary','tertiary_link') THEN 'tertiary_construction'
          WHEN construction IN ('minor','minor_link','OTHERS') THEN 'minor_construction'
          ELSE 'minor_construction' -- like this ?
        END)
      WHEN highway IN ('motorway','trunk','primary','secondary','tertiary',
        'service','track','raceway') THEN highway||(CASE WHEN construction IS NOT NULL
        AND construction !='no' THEN '_construction' ELSE '' END)
      WHEN highway IN ('unclassified','residential','living_street') THEN 'minor'||(
        CASE WHEN construction IS NOT NULL
        AND construction !='no' THEN '_construction' ELSE '' END)
      WHEN highway IN ('road') THEN 'unknown'
      WHEN highway IN ('motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')
        THEN substring(highway,'([a-z]+)')
      WHEN route IN ('bicycle') OR highway IN ('cycleway') THEN 'bicycle_route' --NOTE:extension
      --WHEN highway IN ('cycleway') THEN 'bicycle_route' -- NOTE:extension, MOVE cycleway->path here
      WHEN highway IN ('path','pedestrian','footway','steps') THEN 'path'||(
        CASE WHEN construction IS NOT NULL
        AND construction !='no' THEN '_construction' ELSE '' END)
      WHEN railway IN ('rail','narrow_gauge','preserved','funicular') THEN 'rail'
      WHEN railway IN ('subway','light_rail','monorail','tram') THEN 'transit'
      WHEN aerialway <> '' THEN 'aerialway'
      WHEN tags->'shipway' <> '' THEN tags->'shipway'
      WHEN man_made <> '' THEN man_made
    END) AS class, 
    (CASE
      WHEN railway IS NOT NULL THEN railway
      WHEN (highway IS NOT NULL OR public_transport IS NOT NULL)
          AND highway IN ('path','pedestrian','footway','cycleway','steps')
        THEN COALESCE(NULLIF(public_transport,''),highway)
      WHEN aerialway IS NOT NULL THEN aerialway
    END) AS subclass,
    (CASE WHEN route IN ('bicycle') THEN
      (CASE tags->'network' WHEN 'icn' THEN 'international'
        WHEN 'ncn' THEN 'national'
        WHEN 'rcn' THEN 'regional'
        WHEN 'lcn' THEN 'local'
      END) --NOTE:extension
      ELSE NULLIF(tags->'network','') END) AS network,
    (CASE
      WHEN bridge IS NOT NULL AND bridge!='no' THEN 'bridge'
      WHEN tunnel IS NOT NULL AND tunnel!='no' THEN 'tunnel'
      WHEN tags->'ford' IS NOT NULL AND (tags->'ford')!='no' THEN 'ford'
    END) AS brunnel,
    (CASE
      WHEN oneway IN ('no') THEN 0
      WHEN oneway IN ('-1') THEN -1
      WHEN oneway IS NOT NULL THEN 1
      ELSE NULL
    END) AS oneway,
    (CASE
      WHEN tags->'ramp' IN ('no','separate') THEN 0
      WHEN tags->'ramp' IN ('yes') THEN 1
      ELSE NULL
    END) AS ramp,
    NULLIF(service,'') AS service,
    CASE WHEN access IN ('no','private') THEN false ELSE NULL END AS access,
    (CASE
      WHEN toll IN ('no') THEN 0
      WHEN toll IS NOT NULL THEN 1
      ELSE 0
    END) AS toll,
    (CASE
      WHEN tags->'expressway' IN ('yes') THEN 1
      ELSE NULL
    END) AS expressway,
    (CASE WHEN bicycle IN ('yes','1','designated','permissive') THEN 1
      WHEN bicycle IN ('no','dismount') THEN 0 ELSE NULL
      --TODO: why not tags->'cycleway' &+ tags->'cycleway:left' and tags->'cycleway:right' ?
    END) AS cycleway, --NOTE: extension
    layer,
    tags->'level' AS level,
    (CASE WHEN tags->'indoor' IN ('yes','1') THEN 1 END) AS indoor,
    -- DO THE ZOOM modulation!
    -- https://github.com/openmaptiles/openmaptiles/blob/master/layers/transportation/transportation.sql
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
    ST_AsMVTGeom({{line.way_v}},bounds_geom) AS geom
    -- TODO: should we use planet_osm_roads ? and planet_osm_polygon nad planet_osm_point ? INCOMPLETE!
  FROM {{line.table_name}}
  WHERE (
    {{line.railway_v}} IN ('rail','narrow_gauge','preserved','funicular','subway','light_rail',
      'monorail','tram')
    OR {{line.highway_v}} IN ('motorway','motorway_link','trunk','trunk_link','primary','primary_link',
      'pedestrian','bridleway','corridor','service','track','raceway','busway',
      'bus_guideway','construction')
    OR ({{line.highway_v}} IN ('path','footway','cycleway','steps') AND z>=13) -- hide paths at lowzoom
    OR ({{line.highway_v}} IN ('unclassified','residential','living_street') AND z>=12) -- hide minorroads
    OR ({{line.highway_v}} IN ('tertiary','tertiary_link','road') AND z>=11)
    OR ({{line.highway_v}} IN ('secondary','secondary_link') AND z>=9)
    OR aerialway IN ('chair_lift','drag_lift','platter','t-bar','gondola','cable_bar',
      'j-bar','mixed_lift')
    OR {{line.route_v}} IN ('bicycle') --NOTE:extension
  ) AND ST_Intersects(way,bounds_geom)) AS unfiltered_zoom
WHERE (z>=14) OR (12<=z AND z<14 AND class NOT IN ('path')) OR
  (10<=z AND z<12 AND class NOT IN ('minor')) OR (z<10 AND class IN ('primary','bicycle_route') AND
    -- extension
    CASE WHEN class='bicycle_route' THEN network IN ('national') ELSE true END);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_z_low_13(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
-- similar to _transportation_z_low_13 but less discriminate because less
--  features are shown anywawys
-- motivation:merge more columns together, because at z>=13 names of
-- roads are not shown anyways, nor bridges etc...
SELECT
{% if with_osm_id %} string_agg(DISTINCT osm_id,',') AS osm_id, {% endif %}
  (array_agg(name))[1] AS name,
  (CASE WHEN (z<12 AND class='primary') OR (z<13 AND class IN ('primary','secondary')) THEN ref
    ELSE NULL
  END) AS ref,class,(array_agg(subclass))[1] AS subclass,
  (array_agg(network))[1] AS network,brunnel,
  (array_agg(oneway))[1] AS oneway,min(ramp) AS ramp,
  (array_agg(service))[1] AS service,
  (array_agg(access))[1] AS access,max(toll) AS toll,
  max(expressway) AS expressway,max(cycleway) AS cycleway,
  layer,(array_agg(level))[1] AS level,
  max(indoor) AS indoor,(array_agg(bicycle))[1] AS bicycle,
  (array_agg(foot))[1] AS foot,(array_agg(horse))[1] AS horse,
  (array_agg(mtb_scale))[1] AS mtb_scale,(array_agg(surface))[1] AS surface,
  ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2)) AS geom
FROM {{omt_func_pref}}_pre_merge_transportation(bounds_geom,z)
GROUP BY(class,ref,brunnel,layer);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_highz(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
SELECT
{% if with_osm_id %} string_agg(DISTINCT osm_id,',') AS osm_id, {% endif %}
  name,ref,class,(array_agg(subclass))[1] AS subclass,
  (array_agg(network))[1] AS network,brunnel,
  oneway,min(ramp) AS ramp,(array_agg(service))[1] AS service,
  access,max(toll) AS toll,max(expressway) AS expressway,
  max(cycleway) AS cycleway,
  layer,(array_agg(level))[1] AS level,
  max(indoor) AS indoor,(array_agg(bicycle))[1] AS bicycle,
  (array_agg(foot))[1] AS foot,(array_agg(horse))[1] AS horse,
  (array_agg(mtb_scale))[1] AS mtb_scale,(array_agg(surface))[1] AS surface,
  ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2)) AS geom
FROM {{omt_func_pref}}_pre_merge_transportation(bounds_geom,z)
-- deduce that a road MAY be candidate for merging if :
--  same name, class and ref accross geometry features
--  FILTER OUT bridge or tunnel segments (those will be rendered differently)
--  FILTER OUT access and oneway: a normal road can become oneway and still have the same name
--  FILTER OUT layer, similar reasoning like bridge/tunnel: renders sections of road diff
--  DO NOT FILTER OUT: indoor: because how would that happen anyways ?
-- then do the merging with unnest(ST_ClusterIntersecting())::multigeometries
-- ST_CollectionExtract(*,2) extracts only line features, ST_LineMerge then merges these
--  multigeometries to single geometries
GROUP BY(name,class,ref,brunnel,oneway,access,layer);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
BEGIN IF (z<13) THEN
  RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_z_low_13(bounds_geom,z);
ELSE
  RETURN QUERY SELECT * FROM {{omt_func_pref}}_transportation_highz(bounds_geom,z);
END IF;
END
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_waterway(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_waterway
AS $$
SELECT name,waterway AS class,
  (CASE
    WHEN {{line.bridge_v}} IS NOT NULL AND {{line.bridge_v}}!='no' THEN 'bridge'
    WHEN {{line.tunnel_v}} IS NOT NULL AND {{line.tunnel_v}}!='no' THEN 'tunnel'
    WHEN {{line.ford_v}} IS NOT NULL AND {{line.ford_v}}!='no' THEN 'ford'
  END) AS brunnel,
  (CASE
    WHEN {{line.intermittent_v}} IN ('yes') THEN 1
    ELSE 0
  END) AS intermittent,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM {{line.table_name}}
WHERE {{line.waterway_v}} IN ('stream','river','canal','drain','ditch')
  AND ST_Intersects({{line.way_v}},bounds_geom);
    --TODO: by-zoom specificities
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_place(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_place
AS $$
SELECT * FROM (
  SELECT 
{% if with_osm_id %} (CASE
      WHEN tablefrom='point' THEN 'n'||osm_id
      WHEN tablefrom='polygon' AND osm_id<0 THEN 'r'||(-osm_id)
      WHEN tablefrom='polygon' AND osm_id>0 THEN'w'||osm_id
    END) AS osm_id, {% endif %}
{% if debug %} way_area, {% endif %}
    name,admin_level::integer AS capital,place AS class,
    (tags->'ISO3166-1') AS iso_a2,
    (CASE WHEN way_area IS NULL
        THEN {{omt_func_pref}}_get_point_admin_enclosing_rank(osm_id)
      ELSE get_rank_by_area(way_area) END)+adjust_rank_by_class(place) AS rank,
    ST_AsMVTGeom((CASE WHEN tablefrom='point' THEN way
      WHEN tablefrom='polygon' THEN ST_Centroid(way) END),bounds_geom) AS geom
  FROM (
    SELECT {{polygon.osm_id}}, -- EVEN if without osm_id : for get_point_admin_enclosing
      {{polygon.name}},{{polygon.place}},{{polygon.admin_level}},
      {{polygon.tags}},{{polygon.way}},
      {{polygon.way_area}},'polygon' AS tablefrom
    FROM {{polygon.table_name}}
    WHERE {{polygon.place_v}} IN ('island')
    UNION ALL
    SELECT {{point.osm_id}},
      {{point.name}},{{point.place}},{{point.admin_level}},{{point.tags}},
      {{point.way}},
      {{omt_func_pref}}_get_point_admin_parent_area({{point.osm_id_v}}) AS way_area,
      'point' AS tablefrom
    FROM {{point.table_name}} 
    WHERE {{point.place_v}} IN ('continent','country','state','province','city','town','village',
      'hamlet','suburb','quarter','neighbourhood','isolated_dwelling','island')
    ) AS layer_place
    WHERE ST_Intersects({{polygon.way_v}},bounds_geom)) AS unfiltered_zoom
  WHERE (z>=14) OR (12<=z AND z<14 AND rank<=8) OR (10<=z AND z<12 AND rank<=5) OR (10>z AND rank<=4);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_get_poi_class_rank(class text)
    RETURNS int AS
$$
SELECT CASE class
           WHEN 'hospital' THEN 20
           WHEN 'railway' THEN 40
           WHEN 'bus' THEN 50
           WHEN 'attraction' THEN 70
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


-- TODO: boundaries ? or rather place: check way_area or described_are for points: very crowded with
-- extremely small villages on lower zoom
-- also make sure z_order AS rank is not detrimental: DO FIRST maybe it's why small villages show
-- on low zooms

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_poi(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_poi
AS $$
  -- TODO: I don't like how named pois override nearby pois, instead they should all show
  -- logos and only at high zoom or onlick show name. see zurich towncentre and compare with
  -- openstreetmap raster style
-- TODO: the rank copmutation and documentation are very unclear and how they are now could be better
-- additional source: https://wiki.openstreetmap.org/wiki/OpenStreetMap_Carto/Symbols#Shops_and_services
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  name,class,subclass,
{% if same_rank_poi_high_zooms %} (CASE WHEN z>=17 THEN 30::int ELSE {%endif%}
  (row_number() OVER (ORDER BY ((CASE
  WHEN name IS NOT NULL THEN -100 ELSE 0 END)+{{omt_func_pref}}_get_poi_class_rank(class)) ASC))::int
{% if same_rank_poi_high_zooms %} END) {%endif%} AS rank,
  agg_stop,{{omt_func_pref}}_text_to_int_null(level) AS level,layer,indoor,geom FROM
(SELECT name,
{% if with_osm_id %} osm_id, {% endif %}
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
	subclass,agg_stop,level,layer,indoor,geom
	FROM (SELECT name,
{% if with_osm_id %} osm_id, {% endif %}
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
		ST_AsMVTGeom(
      (CASE WHEN tablefrom = 'point' THEN way
      WHEN tablefrom='polygon' THEN ST_Centroid(way) END)
      ,bounds_geom) AS geom
	FROM (
    SELECT
{% if with_osm_id %} 'n'||osm_id AS osm_id, {% endif %}
      {{point.name}},{{point.waterway}},{{point.building}},{{point.shop}},
      {{point.highway}},{{point.leisure}},{{point.historic}},
      {{point.railway}},{{point.sport}},{{point.office}},{{point.tourism}},
      {{point.landuse}},{{point.barrier}},{{point.amenity}},{{point.aerialway}},
      {{point.level}},{{point.indoor}},{{point.layer}},{{point.way}},
      'point' AS tablefrom FROM {{point.table_name}}
    UNION ALL
    SELECT
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
      {{polygon.name}},{{polygon.waterway}},{{polygon.building}},{{polygon.shop}},
      {{polygon.highway}},{{polygon.leisure}},{{polygon.historic}},
      {{polygon.railway}},{{polygon.sport}},{{polygon.office}},{{polygon.tourism}},
      {{polygon.landuse}},{{polygon.barrier}},{{polygon.amenity}},{{polygon.aerialway}},
      {{polygon.level}},{{polygon.indoor}},{{polygon.layer}},{{polygon.way}},
      'polygon' AS tablefrom FROM {{polygon.table_name}}
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
		) AND ST_Intersects(way,bounds_geom)) AS without_rank_without_class) AS without_rank;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION {{omt_func_pref}}_water(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_named_water
AS $$
SELECT {{polygon.name}},osm_id AS id, --TODO: move this to with_osm_id template arg ?
  (CASE
    WHEN {{polygon.water_v}} IN ('river') THEN 'river'
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
    WHEN {{polygon.ford_v}} IS NOT NULL AND {{polygon.ford_v}}!='no' THEN 'ford'
  END) AS brunnel,
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom) AS geom
FROM {{polygon.table_name}}
WHERE ({{polygon.covered_v}} IS NULL OR {{polygon.covered_v}} != 'yes') AND (
    {{polygon.water_v}} IN ('river') OR {{polygon.waterway_v}} IN ('dock')
    OR {{polygon.natural_v}} IN ('water','bay','spring') OR {{polygon.leisure_v}} IN ('swimming_pool')
    OR {{polygon.landuse_v}} IN ('reservoir','basin','salt_pond'))
  AND ST_Intersects({{polygon.way_v}},bounds_geom);
    --TODO: by-zoom specificities
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_all_func}}(z integer, x integer, y integer)
RETURNS bytea
AS $$
-- ST_TileEnvelope will be cached:
-- SELECT pg_get_functiondef('st_tileenvelope'::regproc) ~ 'IMMUTABLE';
WITH
  premvt_aerodrome_label AS(
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_aerodrome_label(ST_TileEnvelope(z,x,y))),
  premvt_aeroway AS(
    SELECT * FROM {{omt_func_pref}}_aeroway(ST_TileEnvelope(z,x,y))),
  premvt_boundary AS (
    SELECT * FROM {{omt_func_pref}}_boundary(ST_TileEnvelope(z,x,y),z)),
  premvt_building AS (
    SELECT * FROM {{omt_func_pref}}_building(ST_TileEnvelope(z,x,y),z)),
  premvt_housenumber AS (
    SELECT * FROM {{omt_func_pref}}_housenumber(ST_TileEnvelope(z,x,y))),
  premvt_landcover AS (
    SELECT * FROM {{omt_func_pref}}_landcover(ST_TileEnvelope(z,x,y),z)),
  premvt_landuse AS (
    SELECT * FROM {{omt_func_pref}}_landuse(ST_TileEnvelope(z,x,y),z)),
  premvt_mountain_peak AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_mountain_peak(ST_TileEnvelope(z,x,y))),
  premvt_park AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_park(ST_TileEnvelope(z,x,y))),
  premvt_place AS (
    SELECT {{additional_name_columns}} *
      {% if debug %} ,z {% endif %}
    FROM {{omt_func_pref}}_place(ST_TileEnvelope(z,x,y),z)),
  premvt_poi AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_poi(ST_TileEnvelope(z,x,y),z)
    ORDER BY(rank) ASC
    LIMIT CASE WHEN z<12 THEN 100 ELSE 10000 END
  ),
  premvt_waterway AS (
    SELECT {{additional_name_columns}} *
    FROM {{omt_func_pref}}_waterway(ST_TileEnvelope(z,x,y),z)),
  -- the generated {layer} and {layer}_name:
  premvt_water AS (
    SELECT * FROM {{omt_func_pref}}_water(ST_TileEnvelope(z,x,y))),
  premvt_transportation AS (
    SELECT * FROM {{omt_func_pref}}_transportation(ST_TileEnvelope(z,x,y),z)),
  premvt_water_noname AS (
    SELECT
      id,class,intermittent,brunnel,geom
    FROM premvt_water
  ),
  premvt_water_name AS (
    SELECT
      name,{{additional_name_columns}}
      -- TODO: WARN! different from water_noname
      intermittent,geom
    FROM premvt_water WHERE name IS NOT NULL
  ),
  premvt_transportation_noname AS (
    SELECT
      {% if with_osm_id %} osm_id, {% endif %}
      network,class,subclass,brunnel,oneway,ramp,service,
      access,toll,expressway,cycleway,level,layer,indoor,bicycle,
      foot,horse,mtb_scale,surface,
      geom
    FROM premvt_transportation
  ),
  premvt_transportation_name AS (
    SELECT
      {% if with_osm_id %} osm_id, {% endif %}
      {{additional_name_columns}}
      name,{{additional_name_columns}}
      ref,length(ref) AS ref_length,
      network,class,subclass,brunnel,level,layer,indoor,
      geom
    FROM premvt_transportation WHERE name IS NOT NULL
  )
SELECT string_agg(foo.mvt,''::bytea) FROM (
  SELECT ST_AsMVT(premvt_aerodrome_label,'aerodrome_label') AS mvt
    FROM premvt_aerodrome_label UNION
  SELECT ST_AsMVT(premvt_aeroway,'aeroway') AS mvt
    FROM premvt_aeroway UNION
  SELECT ST_AsMVT(premvt_boundary,'boundary') AS mvt
    FROM premvt_boundary UNION
  SELECT ST_AsMVT(premvt_building,'building') AS mvt
    FROM premvt_building UNION
  SELECT ST_AsMVT(premvt_housenumber,'housenumber') AS mvt
    FROM premvt_housenumber UNION
  SELECT ST_AsMVT(premvt_landcover,'landcover') AS mvt
    FROM premvt_landcover UNION
  SELECT ST_AsMVT(premvt_landuse,'landuse') AS mvt
    FROM premvt_landuse UNION
  SELECT ST_AsMVT(premvt_mountain_peak,'mountain_peak') AS mvt
    FROM premvt_mountain_peak UNION
  SELECT ST_AsMVT(premvt_park,'park') AS mvt
    FROM premvt_park UNION
  SELECT ST_AsMVT(premvt_place,'place') AS mvt
    FROM premvt_place UNION
  SELECT ST_AsMVT(premvt_poi,'poi') AS mvt
    FROM premvt_poi UNION
  SELECT ST_AsMVT(premvt_transportation_noname,'transportation') AS mvt
    FROM premvt_transportation_noname UNION
  SELECT ST_AsMVT(premvt_transportation_name,'transportation_name') AS mvt
    FROM premvt_transportation_name UNION
  SELECT ST_AsMVT(premvt_water_noname,'water') AS mvt
    FROM premvt_water_noname UNION
  SELECT ST_AsMVT(premvt_water_name,'water_name') AS mvt
    FROM premvt_water_name UNION
  SELECT ST_AsMVT(premvt_waterway,'waterway') AS mvt
    FROM premvt_waterway
) AS foo;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


SELECT length({{omt_all_func}}(16,34303,22938));

