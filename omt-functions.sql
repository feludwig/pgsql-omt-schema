
-- TODO: 
--  move all column names to templated column names for tags lookup and possibly column different
--    semantics -> "highway" becomes {{ line.highway }}

--  move all table names to templated table names

-- add template prefix for function names, default [ omt_func_pref='omt' ]_transportation
-- add templ prefix for typenames, default [ omt_typ_pref='row_omt' ]_named_transportation
-- add templ "all" function name [ omt_all_func='omt_all' ]

-- the template {{ additional_name_columns }} == 'name AS "name:latin",' eg for osm_bright
--    or could also be 'name AS name_en'.
--    set additional_name_columns='' to not have any effect

-- I give up: aggregate geometries!
--  to do on roads at low zooms, to prevent multiple refs shown for the same road

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
  name text,
  --TODO: name_en ?
  class text,
  iata text,
  icao text,
  ele integer,
  -- not to do: ele_ft
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_aeroway AS (
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
  colour text, -- in format '#rrggbb'
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
  name text,
  -- TODO: name_en, name_de ?
  class text,
  ele integer, -- TODO: maybe real ?
  -- not to do: ele_ft, customary_fr
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_park AS (
  name text,
  --TODO: name_en ?
  class text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_place AS (
{% if with_osm_id %} osm_id text, {% endif %}
{% if debug %} way_area real, {% endif %}
  name text,
  --TODO: name_en ?
  capital integer,
  class text,
  iso_a2 text,
  rank integer,
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_poi AS (
{% if with_osm_id %} osm_id text, {% endif %}
  name text,
  -- TODO: name_en ?
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
  --TODO: name_en ?
  id bigint,
  class text,
  intermittent integer,
  brunnel text, --TODO: only two-possibility, NOT ford
  geom geometry
);

CREATE TYPE {{omt_typ_pref}}_waterway AS (
  name text,
  --TODO: name_en ?
  class text,
  brunnel text, -- TODO: only two-value possible
  intermittent integer,
  geom geometry
);



--utilities
CREATE OR REPLACE FUNCTION text_to_real_0(data text) RETURNS real
AS $$
SELECT CASE
  WHEN data~E'^\\d+(\\.\\d+)?$' THEN data::real
  WHEN data~E'^\\.\\d+$' THEN ('0'||data)::real -- '.9' -> '0.9' -> 0.9
  ELSE 0.0 END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION text_to_int_null(data text) RETURNS integer
AS $$
SELECT CASE
  WHEN data~E'^\\d$' THEN data::integer
  ELSE NULL END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION get_rank_by_area(area real) RETURNS int
AS $$
SELECT CASE WHEN v.val<1 THEN 1 ELSE v.val END
  FROM (SELECT -1*log(20.0,area::numeric)::int+10 AS val) AS v;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION adjust_rank_by_class(class text) RETURNS int
AS $$
SELECT CASE 
  WHEN class IN ('continent','country','state') THEN -2
  WHEN class IN ('province','city') THEN -1
  WHEN class IN ('village') THEN +1
  WHEN class IN ('hamlet','subrb','quarter','neighbourhood') THEN +2
  WHEN class IN ('isolated_dwelling') THEN +3
    -- island, town
  ELSE 0
END;
$$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION get_point_admin_parent_area(node_id bigint) RETURNS real
AS $$
  SELECT way_area FROM (SELECT id
    FROM planet_osm_rels WHERE planet_osm_member_ids(members,'N'::char(1)) && ARRAY[node_id]::bigint[]
    AND (members @> ('[{"type":"N","ref":'||node_id||',"role":"admin_centre"}]')::jsonb
      OR members @> ('[{"type":"N","ref":'||node_id||',"role":"admin_center"}]')::jsonb)
  ) AS parents
  JOIN planet_osm_polygon ON -parents.id=osm_id ORDER BY(way_area) DESC LIMIT 1;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION get_point_admin_enclosing_rank(node_id bigint) RETURNS int
  -- a neighbourhood is not the admin_centre of anything. instead take its enclosing lowest
  -- admin level. add 1 to the rank to signify smaller than the administrative boundary
  -- BUT if the name is the same for that admin level, take ist rank (+0)
AS $$
WITH enclosing_area AS (
  SELECT way_area,(SELECT {{point.name}} FROM {{point.table_name}}
      WHERE {{point.osm_id}}=node_id)=name AS samename
    FROM {{polygon.table_name}} WHERE {{polygon.boundary}}='administrative'
      AND ST_Intersects(way,(SELECT {{point.way}} FROM {{point.table_name}}
          WHERE {{point.osm_id}}=node_id))
    ORDER BY(admin_level) DESC LIMIT 1)
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
    WHEN landuse IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail') THEN landuse
    WHEN amenity IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') THEN
      CASE amenity WHEN 'grave_yard' THEN 'cemetery' ELSE amenity END
    WHEN leisure IN ('stadium','pitch','playground','track') THEN leisure
    WHEN tourism IN ('theme_park','zoo') THEN tourism
    WHEN place IN ('suburbquarter','neighbourhood') THEN place
    WHEN waterway IN ('dam') THEN waterway
  END) AS class,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE (landuse IN ('railway','cemetery','miltary','quarry','residential','commercial',
      'industrial','garages','retail')
  OR leisure IN ('stadium','pitch','playground','track')
  OR tourism IN ('theme_park','zoo') OR place IN ('suburbquarter','neighbourhood')
  OR amenity IN ('bus_station','school','university','kindergarden','college',
      'library','hospital','grave_yard') OR waterway IN ('dam')
  ) AND ST_Intersects(way,bounds_geom) AND (
    (z>=14 OR way_area>1500)
    AND (z>=11 OR way_area>8000)
  );
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_aeroway(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_aeroway
AS $$
SELECT ref,aeroway AS class,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE aeroway IS NOT NULL AND ST_Intersects(way,bounds_geom);
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
    (z>=14 OR way_area>1500) AND
    (z>=12 OR way_area>8000)
  )) AS foo;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION {{omt_func_pref}}_building(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_building
AS $$
SELECT text_to_real_0(tags->'height') AS render_height,
  COALESCE(text_to_real_0(tags->'min_height'),
    text_to_real_0(tags->'building:levels')*2.5)::real AS render_min_height,
  '#ffff00' AS colour,
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
  ST_AsMVTGeom({{line.way}},bounds_geom) AS geom
FROM {{line.table_name}}
WHERE ({{line.boundary}} IN ('administrative') OR CASE
    WHEN z<=4 THEN {{line.boundary}} IN ('maritime')
      AND {{line.admin_level}} IN ('1','2') ELSE false
    END)
   AND (z>=11 OR admin_level IN ('1','2','3','4','5','6','7'))
   AND (z>=8 OR admin_level IN ('1','2','3','4'))
   AND (z>=2 OR admin_level IN ('1','2','3'))
   AND ST_Intersects(way,bounds_geom);
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
  SELECT "addr:housenumber",way,'point' AS tablefrom FROM planet_osm_point
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
    NULLIF({{line.bicycle}},'') AS bicycle,
    NULLIF({{line.foot}},'') AS foot,
    NULLIF({{line.horse}},'') AS horse,
    NULLIF({{line.mtb_scale}},'') AS mtb_scale,
    (CASE WHEN {{line.surface}} IN ('paved','asphalt','cobblestone','concrete',
        'concrete:lanes','concrete:plates','metal','paving_stones','sett',
        'unhewn_cobblestone','wood') THEN 'paved'
      WHEN surface IN ('unpaved','compacted','dirt','earth','fine_gravel',
        'grass','grass_paver','grass_paved','gravel','gravel_turf','ground',
        'ice','mud','pebblestone','salt','sand','snow','woodchips') THEN 'unpaved'
    END) AS surface,
    ST_AsMVTGeom({{line.way}},bounds_geom) AS geom
  FROM {{line.table_name}}
  WHERE (
    {{line.railway}} IN ('rail','narrow_gauge','preserved','funicular','subway','light_rail',
      'monorail','tram')
    OR {{line.highway}} IN ('motorway','motorway_link','trunk','trunk_link','primary','primary_link',
      'pedestrian','bridleway','corridor','service','track','raceway','busway',
      'bus_guideway','construction')
    OR ({{line.highway}} IN ('path','footway','cycleway','steps') AND z>=13) -- hide paths at lowzoom
    OR ({{line.highway}} IN ('unclassified','residential','living_street') AND z>=12) -- hide minorroads
    OR ({{line.highway}} IN ('tertiary','tertiary_link','road') AND z>=11)
    OR ({{line.highway}} IN ('secondary','secondary_link') AND z>=9)
    OR aerialway IN ('chair_lift','drag_lift','platter','t-bar','gondola','cable_bar',
      'j-bar','mixed_lift')
    OR route IN ('bicycle') --NOTE:extension
  ) AND ST_Intersects(way,bounds_geom)) AS unfiltered_zoom
WHERE (z>=14) OR (12<=z AND z<14 AND class NOT IN ('path')) OR
  (10<=z AND z<12 AND class NOT IN ('minor')) OR (z<10 AND class IN ('primary','bicycle_route') AND
    -- extension
    CASE WHEN class='bicycle_route' THEN network IN ('national') ELSE true END);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION {{omt_func_pref}}_transportation(bounds_geom geometry,z integer)
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
GROUP BY(name,class,ref,brunnel,oneway,access,layer);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION {{omt_func_pref}}_waterway(bounds_geom geometry,z integer)
RETURNS setof {{omt_typ_pref}}_waterway
AS $$
SELECT name,waterway AS class,
  (CASE
    WHEN bridge IS NOT NULL AND bridge!='no' THEN 'bridge'
    WHEN tunnel IS NOT NULL AND tunnel!='no' THEN 'tunnel'
    WHEN tags->'ford' IS NOT NULL AND (tags->'ford')!='no' THEN 'ford'
  END) AS brunnel,
  (CASE
    WHEN {{line.intermittent}} IN ('yes') THEN 1
    ELSE 0
  END) AS intermittent,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM {{line.table_name}}
WHERE waterway IN ('stream','river','canal','drain','ditch')
  AND ST_Intersects(way,bounds_geom);
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
        THEN get_point_admin_enclosing_rank(osm_id)
      ELSE get_rank_by_area(way_area) END)+adjust_rank_by_class(place) AS rank,
    ST_AsMVTGeom((CASE WHEN tablefrom='point' THEN way
      WHEN tablefrom='polygon' THEN ST_Centroid(way) END),bounds_geom) AS geom
  FROM (
    SELECT osm_id,
      name,place,admin_level,tags,z_order,way,
      way_area,'polygon' AS tablefrom
    FROM planet_osm_polygon
    WHERE place IN ('island')
    UNION ALL
    SELECT osm_id,
      name,place,admin_level,tags,z_order,way,
      get_point_admin_parent_area(osm_id) AS way_area,
      'point' AS tablefrom
    FROM planet_osm_point 
    WHERE place IN ('continent','country','state','province','city','town','village',
      'hamlet','subrb','quarter','neighbourhood','isolated_dwelling','island')
    ) AS layer_place
    -- TODO: fix zürich affoltern not showing
    -- TODO: does zürich city have multiple centroids ? maybe the polygon and the point are both showing...
  -- distinguish tablefrom='point' -> WHERE place [only] IN ('island') ?
    WHERE ST_Intersects(way,bounds_geom)) AS unfiltered_zoom
  WHERE (z>=14) OR (12<=z AND z<14 AND rank<=8) OR (10<=z AND z<12 AND rank<=5) OR (10>z AND rank<=4);
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION get_poi_class_rank(class text)
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

CREATE OR REPLACE FUNCTION {{omt_func_pref}}_poi(bounds_geom geometry)
RETURNS setof {{omt_typ_pref}}_poi
AS $$
  -- TODO: weiningen the farm does not show. also check maplibre-basic, osm-bright
  --    and osm-liberty styles
SELECT
{% if with_osm_id %} osm_id, {% endif %}
  name,class,subclass,
  (row_number() OVER (ORDER BY ((CASE
  WHEN name IS NOT NULL THEN 600 ELSE 0 END)+get_poi_class_rank(class)) DESC))::int AS rank,
  agg_stop,text_to_int_null(level) AS level,layer,indoor,geom FROM
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
			'weapons','wholesale') THEN 'shop'
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
		tags->'level' AS level,layer,
		(CASE WHEN tags->'indoor' IN ('yes','1') THEN 1 END) AS indoor,
		ST_AsMVTGeom(
      (CASE WHEN tablefrom = 'point' THEN way
      WHEN tablefrom='polygon' THEN ST_Centroid(way) END)
      ,bounds_geom) AS geom
	FROM (
    SELECT name,waterway,building,shop,highway,leisure,historic,
{% if with_osm_id %} 'n'||osm_id AS osm_id, {% endif %}
      railway,sport,office,tourism,landuse,barrier,amenity,
      aerialway,tags,layer,way,'point' AS tablefrom FROM planet_osm_point
    UNION ALL
    SELECT name,waterway,building,shop,highway,leisure,historic,
{% if with_osm_id %}
  (CASE WHEN osm_id<0 THEN 'r'||(-osm_id) WHEN osm_id>0 THEN 'w'||osm_id END) AS osm_id,
{% endif %}
      railway,sport,office,tourism,landuse,barrier,amenity,
      aerialway,tags,layer,way,'polygon' AS tablefrom FROM planet_osm_polygon) AS layer_poi
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
			'watches','weapons','wholesale','wine')
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
SELECT name,osm_id AS id,
  (CASE
    WHEN water IN ('river') THEN 'river'
    WHEN waterway IN ('dock') THEN 'dock'
    WHEN leisure IN ('swimming_pool') THEN 'swimming_pool'
    ELSE 'lake'
  END) AS class,
  (CASE
    WHEN intermittent IN ('yes') THEN 1
    ELSE 0
  END) AS intermittent,
  (CASE
    WHEN bridge IS NOT NULL AND bridge!='no' THEN 'bridge'
    WHEN tunnel IS NOT NULL AND tunnel!='no' THEN 'tunnel'
    WHEN tags->'ford' IS NOT NULL AND (tags->'ford')!='no' THEN 'ford'
  END) AS brunnel,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE (covered IS NULL OR covered != 'yes') AND (
    water IN ('river') OR waterway IN ('dock') OR leisure IN ('swimming_pool')
    OR "natural" IN ('water','bay','spring') OR leisure IN ('swimming_pool')
    OR landuse IN ('reservoir','basin','salt_pond'))
  AND ST_Intersects(way,bounds_geom);
    --TODO: by-zoom specificities
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION {{omt_all_func}}(z integer, x integer, y integer)
RETURNS bytea
AS $$
DECLARE
    result bytea;
    bounds_geom geometry;
BEGIN
    SELECT ST_TileEnvelope(z,x,y) INTO bounds_geom;
    WITH
      premvt_transportation AS (
        SELECT * FROM {{omt_func_pref}}_transportation(bounds_geom,z)),
      premvt_aeroway AS(
        SELECT * FROM {{omt_func_pref}}_aeroway(bounds_geom)),
      premvt_boundary AS (
        SELECT * FROM {{omt_func_pref}}_boundary(bounds_geom,z)),
      premvt_building AS (
        SELECT * FROM {{omt_func_pref}}_building(bounds_geom,z)),
      premvt_housenumber AS (
        SELECT * FROM {{omt_func_pref}}_housenumber(bounds_geom)),
      premvt_landuse AS (
        SELECT * FROM {{omt_func_pref}}_landuse(bounds_geom,z)),
      premvt_landcover AS (
        SELECT * FROM {{omt_func_pref}}_landcover(bounds_geom,z)),
      premvt_park AS (
        SELECT {{additional_name_columns}} *
        FROM {{omt_func_pref}}_park(bounds_geom)),
      premvt_place AS (
        SELECT {{additional_name_columns}} *
          {% if debug %} ,z {% endif %}
        FROM {{omt_func_pref}}_place(bounds_geom,z)),
      premvt_poi AS (
        SELECT {{additional_name_columns}} *
        FROM {{omt_func_pref}}_poi(bounds_geom)),
      premvt_water AS (
        SELECT * FROM {{omt_func_pref}}_water(bounds_geom)),
      premvt_waterway AS (
        SELECT {{additional_name_columns}} *
        FROM {{omt_func_pref}}_waterway(bounds_geom,z)),
      -- the generated {layer} and {layer}_name:
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
      SELECT ST_AsMVT(premvt_aeroway,'aeroway') AS mvt
        FROM premvt_aeroway UNION
      SELECT ST_AsMVT(premvt_boundary,'boundary') AS mvt
        FROM premvt_boundary UNION
      SELECT ST_AsMVT(premvt_building,'building') AS mvt
        FROM premvt_building UNION
      SELECT ST_AsMVT(premvt_housenumber,'housenumber') AS mvt
        FROM premvt_housenumber UNION
      SELECT ST_AsMVT(premvt_landuse,'landuse') AS mvt
        FROM premvt_landuse UNION
      SELECT ST_AsMVT(premvt_landcover,'landcover') AS mvt
        FROM premvt_landcover UNION
      SELECT ST_AsMVT(premvt_park,'park') AS mvt
        FROM premvt_park UNION
      SELECT ST_AsMVT(premvt_place,'place') AS mvt
        FROM premvt_place UNION
      SELECT ST_AsMVT(premvt_poi,'poi') AS mvt
        FROM premvt_poi UNION
      SELECT ST_AsMVT(premvt_waterway,'waterway') AS mvt
        FROM premvt_waterway UNION
      SELECT ST_AsMVT(premvt_water_noname,'water') AS mvt
        FROM premvt_water_noname UNION
      SELECT ST_AsMVT(premvt_water_name,'water_name') AS mvt
        FROM premvt_water_name UNION
      SELECT ST_AsMVT(premvt_transportation_noname,'transportation') AS mvt
        FROM premvt_transportation_noname UNION
      SELECT ST_AsMVT(premvt_transportation_name,'transportation_name') AS mvt
        FROM premvt_transportation_name
    ) AS foo INTO result;
    RETURN result;
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

-- TODO: landuse or landcover, debug: where are vineyards and why are they not showing ?


SELECT length({{omt_all_func}}(16,34303,22938));

