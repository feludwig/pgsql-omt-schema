
-- TEMPLATE usage:
-- need to define variables in run.py, then
-- syntax is: {% if with_osm_id %} SQL STATEMENT1 {% else %} SQL STATEMENT2 {% endif %}
--    where with_osm_id is a boolean variable
-- other syntax: {{ omt_func_pref }}
--    where omt_func_pref is a text variable

-- WARNING: only one curly brace pair used in this explanation to not confuse templating engine, use 2 pairs
-- VARIABLES available :
--  {point} the table storing all point features, default osm2pgsql name planet_osm_point
--    -> FROM {point.table_name}
--    -> SELECT {point.<column_name>} FROM ...
--        this becomes "(tags->'col') AS col" when col was not detected in db, and "col AS col" otherwise
--    -> WHERE {point.<column_name>_v}*2==7 AND ... [v for "value"] removes the "AS"
--        this becomes "(tags->'col')" when col was not detected, and "col" otherwise
--    -> WHERE {point.<column_name>_ne} OR ... [ne for "not exists"] tests IS NULL
--        this becomes "(NOT (tags?'col'))" when col was not detected, and "col IS NULL" otherwise
--  {line} the table storing all line features, default osm2pgsql name planet_osm_line
--    -> exaclty like {point}, there is a {line.table_name} and
--    -> {line.<column_name>}, {line.<column_name>_v} {line.<column_name>_ne}
--  {polygon} the table storing all line features, default osm2pgsql name planet_osm_polygon
--    -> exaclty like {point}, there is a {polygon.table_name} and
--    -> {polygon.<column_name>} and {polygon.<column_name>_v}
--  ALSO: any column name {point.<colname>_ne} ["not exists"] is a shorthand for
--    ({point.<colname>_v} is null), which gets contracted to "tags"?<colname> in case of tags


-- TODO:
--  *move all table names to templated table names
--  *check 5432 database: working well
--  * INDEXer: hardcode the way_area conditions away and INDEX ON GIST(way), way_area
--    this should be nicer than all the way_area>24e3, way_area>360e3 etc.. separate indexes...

-- zoom filtering:
--  water features filter out by area
--  water line features: remove at z<13
-- landcover z>=7 else empty
-- landuse empty ? z>=11 ?

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
CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_real_null(data text) RETURNS real
AS $$
SELECT CASE
  WHEN data~E'^\\d+(\\.\\d+)?$' THEN data::real
  WHEN data~E'^\\.\\d+$' THEN ('0'||data)::real -- '.9'::text -> '0.9'::text -> 0.9::real
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_text_to_int_null(data text) RETURNS integer
AS $$
SELECT CASE
  WHEN data~E'^\\d+$' THEN data::integer
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
SELECT {{polygon.way_area}}
FROM {{polygon.table_name}} WHERE {{polygon.boundary_v}}='administrative'
    AND ST_Intersects(way,(SELECT {{point.way}} FROM {{point.table_name}}
        WHERE {{point.osm_id_v}}=node_id))
  ORDER BY({{polygon.way_area_v}}) ASC LIMIT 1;
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
  SELECT CASE WHEN enclosing_area.samename=true THEN {{omt_func_pref}}_get_rank_by_area(way_area)
    ELSE
      {{omt_func_pref}}_get_rank_by_area(way_area)+1
    END FROM enclosing_area;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;




CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landuse(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landuse
AS $$
SELECT
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
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
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom) AS geom
FROM {{polygon.table_name}}
WHERE ({{polygon.landuse_v}} IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail')
  OR {{polygon.leisure_v}} IN ('stadium','pitch','playground','track')
  OR {{polygon.tourism_v}} IN ('theme_park','zoo') OR {{polygon.place_v}} IN ('suburbquarter','neighbourhood')
  OR {{polygon.amenity_v}} IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') OR {{polygon.waterway_v}} IN ('dam')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
    (z>=12 AND {{polygon.way_area_v}}>1500) OR
    (z>=11 AND {{polygon.way_area_v}}>6000) OR
    (z>=10 AND {{polygon.way_area_v}}>24e3) OR
    (z>=09 AND {{polygon.way_area_v}}>96e3) OR
    (z>=08 AND {{polygon.way_area_v}}>384e3) OR
    (z>=07 AND {{polygon.way_area_v}}>1536e3) OR
    (z>=06 AND {{polygon.way_area_v}}>6e6) OR
    (z>=05 AND {{polygon.way_area_v}}>24e6) OR
    (z>=04 AND {{polygon.way_area_v}}>96e6)
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
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM (
  SELECT
{% if with_osm_id %} ('n'||{{point.osm_id_v}}) AS osm_id, {% endif %}
    {{point.name}},{{point.aeroway_v}},{{point.aerodrome_type}},
    {{point.iata}},{{point.icao}},{{point.ele}},{{point.way}}
  FROM {{point.table_name}}
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
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
WHERE ST_Intersects(way,bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_landcover(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_landcover
AS $$
SELECT
{% if with_osm_id %} string_agg(osm_id,',') AS osm_id, {% endif %}
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
  -- well this seems to work, GROUP BY twice!
  ST_AsMVTGeom(ST_Union(way_multipoly),bounds_geom) AS geom
FROM (SELECT
{% if with_osm_id %}
  string_agg(CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END,',') AS osm_id,
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
  unnest(ST_ClusterIntersecting(way)) AS way_multipoly
  FROM {{polygon.table_name}}
  WHERE ({{polygon.landuse_v}} IN ('allotments','farm','farmland','orchard','plant_nursery','vineyard',
    'grass','grassland','meadow','forest','village_green','recreation_ground')
  OR {{polygon.natural_v}} IN ('wood','wetland','fell','grassland','heath','scrub','shrubbery','tundra',
    'glacier','bare_rock','scree','beach','sand','dune')
  OR {{polygon.leisure_v}} IN ('park','garden','golf_course')
  OR {{polygon.wetland_v}} IN ('bog','swamp','wet_meadow','marsh','reedbed','slatern','tidalflat','saltmarsh','mangrove')
  ) AND ST_Intersects({{polygon.way_v}},bounds_geom) AND (
    (z>=12 AND {{polygon.way_area_v}}>1500) OR
    (z>=11 AND {{polygon.way_area_v}}>6000) OR
    (z>=10 AND {{polygon.way_area_v}}>24e3) OR
    (z>=09 AND {{polygon.way_area_v}}>96e3) OR
    (z>=08 AND {{polygon.way_area_v}}>384e3) OR
    (z>=07 AND {{polygon.way_area_v}}>1536e3) OR
    (z>=06 AND {{polygon.way_area_v}}>6e6) OR
    (z>=05 AND {{polygon.way_area_v}}>24e6) OR
    (z>=04 AND {{polygon.way_area_v}}>96e6)
  )
  GROUP BY({{polygon.wetland_v}},{{polygon.landuse_v}},{{polygon.leisure_v}},{{polygon.natural_v}})
) AS foo
GROUP BY(class,subclass);
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
  ST_AsMVTGeom({{polygon.way_v}},bounds_geom) AS geom
FROM {{polygon.table_name}}
WHERE NOT {{polygon.building_ne}}
  AND (NOT {{polygon.location_v}} ~ 'underground' OR {{polygon.location_ne}})
  AND ST_Intersects({{polygon.way_v}},bounds_geom)
  AND (
    (z>=14 OR {{polygon.way_area_v}}>=200) AND (z>12) -- show no buildings above z>=12
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
{% if with_osm_id %} ('n'||{{point.osm_id_v}}) AS osm_id, {% endif %}
    {{point.name}},{{point.ele_ct}},{{point.way}},
    -- score of 0 means popular item: should be shown first
    ({{point.wikipedia_ne}}::int+{{point.wikidata_ne}}::int) AS score,
    {{point.natural_v}} AS class
  FROM {{point.table_name}}
  WHERE {{point.natural_v}} IN ('peak','volcano','saddle')
  UNION ALL
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
    WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
{% endif %}
    {{line.name}},{{line.ele_ct}},{{line.way}},
    -- score of 0 means popular item: should be shown first
    ({{line.wikipedia_ne}}::int+{{line.wikidata_ne}}::int) AS score,
    {{line.natural_v}} AS class
  FROM {{line.table_name}}
  WHERE {{line.natural_v}} IN ('ridge','cliff','arete')
    ) AS foo
WHERE ST_Intersects(way,bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_pre_country_boundary(bounds_geom geometry, z integer)
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
    COALESCE({{line.iso3166_1_alpha2_v}},{{line.iso3166_1_v}},{{line.country_code_fips_v}})
    ELSE NULL END) AS claimed_by,
  (CASE {{line.boundary_v}} WHEN 'maritime' THEN 1 ELSE 0 END) AS maritime,
  {{line.way_v}} AS geom -- WARNING: abusive cast, still ST_AsMVTGeom(geom) missing
FROM {{line.table_name}}
WHERE ({{line.boundary_v}} IN ('administrative','disputed')
    OR (z<=4 AND ({{line.boundary_v}} IN ('maritime')
      AND {{line.admin_level_v}} IN ('1','2'))))
   AND (z>=11 OR {{line.admin_level_v}} IN ('1','2','3','4','5','6','7'))
   AND (z>=8 OR {{line.admin_level_v}} IN ('1','2','3','4'))
   AND (z>=2 OR {{line.admin_level_v}} IN ('1','2','3'))
   AND ST_Intersects({{line.way_v}},bounds_geom);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_boundary(bounds_geom geometry, z integer)
RETURNS setof {{omt_typ_pref}}_boundary
AS $$
WITH pre_country AS (
  SELECT
{% if with_osm_id %} osm_id, {% endif %}
    admin_level,disputed,disputed_name,claimed_by,maritime,geom
  FROM {{omt_func_pref}}_pre_country_boundary(bounds_geom,z)
--    -- this algorithm tries to find out the country name on the left and right sides
--    -- of the boundary.
--    -- TODO: slow performance, create a MATERIALIZED VIEW for the just-country ones ?
--    -- for querying then just SELECT from matview wherever admin_level<=2
--  ),
--  namesides AS (
--    -- TODO: this still fails with way 124997929
--    SELECT
--  {% if with_osm_id %} pre_country.osm_id AS osm_id, {% endif %}
--      -- the group by collapses row ordering. but we only want the highest-log_int_of_area
--      -- and highest-admin_level value first (eventually EXTENSION: described below, take multiple names
--      -- of the counrty first, then ||' '|| also the province name, ||' '|| county name etc..)
--      -- and we want ORDER BY(log_int_of_area) DESC, so flip it
--
--      -- for debugging the name-resolution :
--      --(array_to_string(array_agg(tosort_name||' lgia'||log_int_of_area::text ORDER BY (99-log_int_of_area)::text||tosort_name ASC),'/'))
--      substring((array_agg(tosort_name ORDER BY (99-log_int_of_area)::text||tosort_name ASC))[1],2)
--      AS name,
--      side,pre_country.admin_level,
--      pre_country.geom
--    FROM (
--      SELECT osm_id,tosort_name,side,area,
--        -- this log_int_of_area is an approximation of area:
--        -- if the left sided area is 50000 and the right is 50, approximate a GROUP BY(simplified_are)
--        -- where round(log(area)) is an appropriate choice: (left_area=53000,adm_l=2,name=abc) and
--        -- (left_area=61000,adm_l=4,name=def) will go toghether as lg_i_a=4
--        -- and actually be selected over (right_area=46,adm_l=1,name=ghi) or (right_area=123,...) with
--        -- lg_i_a=1.
--        -- TRY not to reach 100, log_int_of_area SHOULD <99! (was 10 and 9 but we can expand like this. now has ample headroom)
--        -- this is because above, the tosort_name is a ::text and is being sorted by.
--        -- because we generate log_int_of_area later, we actually sort by log_int_of_area||tosort_name.
--        (log(15.0,area::numeric)::int) AS log_int_of_area
--      FROM (
--        SELECT
--          pre_country.osm_id AS osm_id, --required osm_id for uniqueness
--          p.admin_level||p.name AS tosort_name,t.val AS side,
--          pre_country.admin_level,
--          -- st_buffer the line geometry to become a polygon, BUT only to left/right side
--          -- of itself. then measure area of overlap with some test boundary polygon.
--          -- if said polygon is on left side of line, the area for side='left' should be >0
--          -- and for side='right' should be =0.
--          -- but with real world data and complicated boundaries that have tight turns,
--          -- left and right may both be nonzero. see order by(log_int_of_area) below for that
--          ST_Area(ST_Intersection(p.way,
--              ST_Buffer(
--                -- below there is a pre_country.admin_level<=2 but just to be
--                -- sure, make NULL here as well
--                CASE WHEN pre_country.admin_level<=0 THEN pre_country.geom ELSE NULL END,
--                2.0,'side='||t.val))) AS area
--        FROM planet_osm_polygon AS p,
--          (VALUES ('left'),('right')) AS t(val),
--          pre_country
--        WHERE
--          p.way && bounds_geom
--          AND pre_country.admin_level<=2
--          AND ST_Intersects(p.way,pre_country.geom)
--          AND p.boundary='administrative' AND p.admin_level IS NOT NULL
--          AND p.admin_level IN ('1','2','3','4','5')
--        ) AS logless_area
--      WHERE area>0.001 --tolerance
--      -- TODO: we should just select the highest log_int_of_area: a GROUP BY(log_int_of_area) ?
--      -- this should enable showing left=Swtizerland/Katon aarau right=Germany/Baden württemberg
--      -- enhanced from the current left=Switzerland right=Germany...
--      ORDER BY
--        -- gather the same features together: ASSUMPTION is that
--        -- osm_id is a unique id: this is not the case... but it's a reasonable assumption because
--        -- the next best thing is to create a hash of the geometry: that's exprensive processing...
--        (logless_area.osm_id),
--        -- take (left_area=53000,adm_l=** 2 **,name=abc) over (left_area=61000,adm_l=** 4 **,name=def)
--        (logless_area.admin_level::integer) ASC,
--        side
--      ) AS deduced
--      JOIN pre_country ON pre_country.osm_id=deduced.osm_id
--  GROUP BY(pre_country.osm_id,deduced.side,pre_country.admin_level,pre_country.geom)
  )
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  admin_level,
--  (CASE WHEN admin_level<=2
--    THEN (SELECT name FROM namesides WHERE side='left' AND pre_country.geom=geom LIMIT 1)
--    ELSE NULL
--  END) AS adm0_l,
--  (CASE WHEN admin_level<=2
--    THEN (SELECT name FROM namesides WHERE side='right' AND pre_country.geom=geom LIMIT 1)
--    ELSE NULL
--  END) AS adm0_r,
  NULL AS adm0_l,NULL AS adm0_r,
  disputed,disputed_name,claimed_by,maritime,
  ST_AsMVTGeom(geom,bounds_geom) AS geom
FROM pre_country;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_housenumber(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_housenumber
AS $$
SELECT housenumber,
  ST_AsMVTGeom((CASE
      WHEN tablefrom = 'point' THEN way
      ELSE ST_Centroid(way) END),bounds_geom) AS geom
FROM (
  SELECT {{line.housenumber}},{{line.way}},'line' AS tablefrom FROM {{line.table_name}}
  UNION ALL
  SELECT {{point.housenumber}},{{point.way}},'point' AS tablefrom FROM {{point.table_name}}
  UNION ALL
  SELECT {{polygon.housenumber}},{{polygon.way}},'polygon' AS tablefrom FROM planet_osm_polygon)
    AS layer_housenumber
  -- obviously don't scan on the ST_Centroid(way) because those are not indexed
WHERE housenumber IS NOT NULL AND ST_Intersects(way,bounds_geom) AND z>=14;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_pre_merge_transportation(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
SELECT * FROM (
  SELECT
{% if with_osm_id %}
  (CASE WHEN {{line.osm_id_v}}<0 THEN 'r'||(-{{line.osm_id_v}})
    WHEN {{line.osm_id_v}}>0 THEN 'w'||{{line.osm_id_v}} END) AS osm_id,
{% endif %}
    {{line.name}},
    {{line.ref}},
  -- from https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
    (CASE
      WHEN {{line.highway_v}} = 'construction' THEN (CASE
          WHEN {{line.construction_v}} IN ('motorway','motorway_link') THEN 'motorway_construction'
          WHEN {{line.construction_v}} IN ('primary','primary_link') THEN 'primary_construction'
          WHEN {{line.construction_v}} IN ('secondary','secondary_link') THEN 'secondary_construction'
          WHEN {{line.construction_v}} IN ('tertiary','tertiary_link') THEN 'tertiary_construction'
          WHEN {{line.construction_v}} IN ('minor','minor_link') THEN 'minor_construction'
          ELSE 'minor_construction' -- when OTHERs
        END)
      WHEN {{line.highway_v}} IN ('motorway','trunk','primary','secondary','tertiary',
        'service','track','raceway') THEN {{line.highway_v}}||(CASE WHEN NOT {{line.construction_ne}}
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      WHEN {{line.highway_v}} IN ('unclassified','residential','living_street') THEN 'minor'||(
        CASE WHEN NOT {{line.construction_ne}}
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      WHEN {{line.highway_v}} IN ('road') THEN 'unknown'
      WHEN {{line.highway_v}} IN ('motorway_link','trunk_link','primary_link','secondary_link','tertiary_link')
        THEN substring({{line.highway_v}},'([a-z]+)')
      WHEN {{line.route_v}} IN ('bicycle') THEN 'bicycle_route' --NOTE:extension
      --WHEN {{line.highway_v}} IN ('cycleway') THEN 'bicycle_route' -- NOTE:extension, MOVE cycleway->path here
      WHEN {{line.highway_v}} IN ('cycleway','path','pedestrian','footway','steps') THEN 'path'||(
        CASE WHEN {{line.construction_v}} IS NOT NULL
        AND {{line.construction_v}} !='no' THEN '_construction' ELSE '' END)
      -- and now non-highways
      WHEN {{line.railway_v}} IN ('rail','narrow_gauge','preserved','funicular') THEN 'rail'
      WHEN {{line.railway_v}} IN ('subway','light_rail','monorail','tram') THEN 'transit'
      WHEN NOT {{line.aerialway_ne}} THEN 'aerialway'
      WHEN NOT {{line.shipway_ne}} THEN {{line.shipway_v}}
      WHEN NOT {{line.man_made_ne}} THEN {{line.man_made_v}}
    END) AS class,
    (CASE
      WHEN NOT {{line.railway_ne}} THEN {{line.railway_v}}
      WHEN NOT {{line.public_transport_ne}} AND {{line.public_transport_v}}!=''
        THEN {{line.public_transport_v}}
      WHEN NOT {{line.highway_ne}} THEN {{line.highway_v}}
      WHEN NOT {{line.aerialway_ne}} THEN {{line.aerialway_v}}
    END) AS subclass,
    (CASE WHEN {{line.route_v}} IN ('bicycle') THEN
      (CASE {{line.network_v}} WHEN 'icn' THEN 'international'
        WHEN 'ncn' THEN 'national'
        WHEN 'rcn' THEN 'regional'
        WHEN 'lcn' THEN 'local'
      END) --NOTE:extension
      ELSE NULLIF({{line.network_v}},'') END) AS network,
    (CASE
      WHEN {{line.bridge_v}} IS NOT NULL AND {{line.bridge_v}}!='no' THEN 'bridge'
      WHEN {{line.tunnel_v}} IS NOT NULL AND {{line.tunnel_v}}!='no' THEN 'tunnel'
      WHEN {{line.ford_v}} IS NOT NULL AND {{line.ford_v}}!='no' THEN 'ford'
    END) AS brunnel,
    (CASE
      WHEN {{line.oneway_v}} IN ('no') THEN 0
      WHEN {{line.oneway_v}} IN ('-1') THEN -1
      WHEN {{line.oneway_v}} IS NOT NULL THEN 1
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
      WHEN NOT {{line.toll_ne}} THEN 1
      ELSE NULL
    END) AS toll,
    (CASE
      WHEN {{line.expressway_v}} IN ('yes') THEN 1
      ELSE NULL
    END) AS expressway,
    (CASE WHEN {{line.bicycle_v}} IN ('yes','1','designated','permissive') THEN 1
      WHEN {{line.bicycle_v}} IN ('no','dismount') THEN 0 ELSE NULL
      --TODO: why not tags->'cycleway' &+ tags->'cycleway:left' and tags->'cycleway:right' ?
    END) AS cycleway, --NOTE: extension
    {{line.layer}},
    {{line.level}},
    (CASE WHEN {{line.indoor_v}} IN ('yes','1') THEN 1 END) AS indoor,
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
    OR {{line.route_v}} IN ('bicycle') --NOTE:extension
  ) AND ST_Intersects(way,bounds_geom)) AS unfiltered_zoom
WHERE (
     (z>=13) -- take everything
  OR (substring(class,'([a-z]+)') IN ('tertiary','minor') AND z>=11)
  OR (substring(class,'([a-z]+)') IN ('secondary','raceway','busway','transit') AND z>=9)
  OR (substring(class,'([a-z]+)') IN ('primary','motorway','trunk','ferry','rail','aerialway') AND z>=3)
    --extension
  OR (class='bicycle_route' AND network='national' AND z>=3)
);
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
{% if with_osm_id %}
{% if transportation_aggregate_osm_id_reduce %}
  (CASE WHEN (array_agg(DISTINCT name))[1] IS NULL THEN NULL
    ELSE string_agg(DISTINCT osm_id,',')
  END) AS osm_id,
{% else %}
  string_agg(DISTINCT osm_id,',') AS osm_id,
{% endif %}
{% endif %}
  (array_agg(DISTINCT name))[1] AS name,
  (CASE WHEN
      (z>=07 AND class IN ('motorway') AND brunnel IS NULL)
      OR (z>=12 AND class IN ('primary','motorway')) THEN ref
    ELSE NULL
  END) AS ref,class,(array_agg(subclass))[1] AS subclass,
  (array_agg(DISTINCT network))[1] AS network,brunnel,
  (array_agg(DISTINCT oneway))[1] AS oneway,min(ramp) AS ramp,
  (array_agg(DISTINCT service))[1] AS service,
  (array_agg(DISTINCT access))[1] AS access,max(toll) AS toll,
  max(expressway) AS expressway,max(cycleway) AS cycleway,
  layer,(array_agg(DISTINCT level))[1] AS level,
  max(indoor) AS indoor,(array_agg(DISTINCT bicycle))[1] AS bicycle,
  (array_agg(DISTINCT foot))[1] AS foot,(array_agg(DISTINCT horse))[1] AS horse,
  (array_agg(DISTINCT mtb_scale))[1] AS mtb_scale,(array_agg(DISTINCT surface))[1] AS surface,
  ST_LineMerge(ST_CollectionExtract(unnest(ST_ClusterIntersecting(geom)),2)) AS geom
FROM {{omt_func_pref}}_pre_merge_transportation(bounds_geom,z)
GROUP BY(class,ref,brunnel,layer);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation_highz(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_named_transportation
AS $$
SELECT
{% if with_osm_id %}
{% if transportation_aggregate_osm_id_reduce %}
  (CASE WHEN (array_agg(DISTINCT name))[1] IS NULL THEN NULL
    ELSE string_agg(DISTINCT osm_id,',')
  END) AS osm_id,
{% else %}
  string_agg(DISTINCT osm_id,',') AS osm_id,
{% endif %}
{% endif %}
  name,ref,class,subclass,
  (array_agg(DISTINCT network))[1] AS network,brunnel,
  oneway,min(ramp) AS ramp,(array_agg(DISTINCT service))[1] AS service,
  access,max(toll) AS toll,max(expressway) AS expressway,
  max(cycleway) AS cycleway,
  layer,(array_agg(DISTINCT level))[1] AS level,
  max(indoor) AS indoor,bicycle,
  (array_agg(DISTINCT foot))[1] AS foot,(array_agg(DISTINCT horse))[1] AS horse,
  (array_agg(DISTINCT mtb_scale))[1] AS mtb_scale,(array_agg(DISTINCT surface))[1] AS surface,
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
GROUP BY(name,class,subclass,ref,brunnel,oneway,access,layer,bicycle);
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
  AND ST_Intersects({{line.way_v}},bounds_geom) AND z>=13;
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
    name,admin_level::integer AS capital,place AS class,
    (tags->'ISO3166-1') AS iso_a2,
    (CASE WHEN way_area IS NULL
        THEN {{omt_func_pref}}_get_point_admin_enclosing_rank(osm_id)
      ELSE {{omt_func_pref}}_get_rank_by_area(way_area) END)+{{omt_func_pref}}_adjust_rank_by_class(place) AS rank,
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
    WHERE ST_Intersects(way,bounds_geom)) AS unfiltered_zoom
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
{% if same_rank_poi_high_zooms %} (CASE WHEN z>=15 THEN 30::int ELSE {%endif%}
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
		ST_AsMVTGeom(way,bounds_geom) AS geom
	FROM (
    SELECT
{% if with_osm_id %} 'n'||{{point.osm_id_v}} AS osm_id, {% endif %}
      {{point.name}},{{point.waterway}},{{point.building}},{{point.shop}},
      {{point.highway}},{{point.leisure}},{{point.historic}},
      {{point.railway}},{{point.sport}},{{point.office}},{{point.tourism}},
      {{point.landuse}},{{point.barrier}},{{point.amenity}},{{point.aerialway}},
      {{point.level}},{{point.indoor}},{{point.layer}},{{point.way}},
      'point' AS tablefrom FROM {{point.table_name}}
    UNION ALL
    SELECT
{% if with_osm_id %}
  (CASE WHEN {{polygon.osm_id_v}}<0 THEN 'r'||(-{{polygon.osm_id_v}})
    WHEN {{polygon.osm_id_v}}>0 THEN 'w'||{{polygon.osm_id_v}} END) AS osm_id,
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
    SELECT * FROM {{omt_func_pref}}_housenumber(ST_TileEnvelope(z,x,y),z)),
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
      --TODO: thow away this id
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
      -- only osm_id if not in transportation_name
      {% if with_osm_id %} (CASE WHEN name IS NULL AND ref IS NULL THEN osm_id END) AS osm_id, {% endif %}
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
      name,
      replace(ref,';',E'\n') AS ref,length(ref) AS ref_length,
      network,class,subclass,brunnel,level,layer,indoor,
      geom
    FROM premvt_transportation WHERE name IS NOT NULL OR ref IS NOT NULL
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


SELECT length({{omt_all_func}}(15,17151,11469));

