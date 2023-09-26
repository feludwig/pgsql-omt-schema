
-- transportation and transportation_name layer types.
-- will be separated in the two layers
DROP TYPE row_omt_aerodrome_label CASCADE;
DROP TYPE row_omt_aeroway CASCADE;
DROP TYPE row_omt_boundary CASCADE;
DROP TYPE row_omt_building CASCADE;
DROP TYPE row_omt_housenumber CASCADE;
DROP TYPE row_omt_landcover CASCADE;
DROP TYPE row_omt_landuse CASCADE;
DROP TYPE row_omt_mountain_peak CASCADE;
DROP TYPE row_omt_park CASCADE;
DROP TYPE row_omt_place CASCADE;
DROP TYPE row_omt_poi CASCADE;
DROP TYPE row_omt_waterway CASCADE;

-- united types to make {layer} and {layer}_name
DROP TYPE row_omt_named_transportation CASCADE;
DROP TYPE row_omt_named_water CASCADE;

-- BEWARE! the order of these columns is important.
-- if you exchange two differently-typed columns, postgresql will not be happy,
-- but the danger is when you exchange two same-type columns: postgresql will
-- happily resturn you the wrong results...

CREATE TYPE row_omt_named_transportation AS (
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

CREATE TYPE row_omt_aerodrome_label AS (
  name text,
  --TODO: name_en ?
  class text,
  iata text,
  icao text,
  ele integer,
  -- not to do: ele_ft
  geom geometry
);

CREATE TYPE row_omt_aeroway AS (
  ref text,
  class text,
  geom geometry
);

CREATE TYPE row_omt_boundary AS (
  admin_level integer,
  adm0_l text,
  adm0_r text,
  disputed integer, --TODO: fix, for now always returning 0
  --disputed_name text,
  claimed_by text,
  maritime integer,
  geom geometry
);

CREATE TYPE row_omt_building AS (
  render_height real,
  render_min_height real,
  colour text, -- in format '#rrggbb'
  hide_3d boolean,
  geom geometry
);

CREATE TYPE row_omt_housenumber AS (
  housenumber text,
  geom geometry
);

CREATE TYPE row_omt_landcover AS (
  class text,
  subclass text,
  geom geometry
);

CREATE TYPE row_omt_landuse AS (
  class text,
  geom geometry
);

CREATE TYPE row_omt_mountain_peak AS (
  name text,
  -- TODO: name_en, name_de ?
  class text,
  ele integer, -- TODO: maybe real ?
  -- not to do: ele_ft, customary_fr
  rank integer,
  geom geometry
);

CREATE TYPE row_omt_park AS (
  name text,
  --TODO: name_en ?
  class text,
  rank integer,
  geom geometry
);

CREATE TYPE row_omt_place AS (
  name text,
  --TODO: name_en ?
  capital integer,
  class text,
  iso_a2 text,
  rank integer,
  geom geometry
);

CREATE TYPE row_omt_poi AS (
  name text,
  -- TODO: name_en ?
  class text,
  subclass text,
  rank integer,
  agg_stop integer,
  level text,
  layer int,
  indoor int,
  geom geometry
);

CREATE TYPE row_omt_named_water AS (
  name text,
  --TODO: name_en ?
  id bigint,
  class text,
  intermittent integer,
  brunnel text, --TODO: only two-possibility, NOT ford
  geom geometry
);

CREATE TYPE row_omt_waterway AS (
  name text,
  --TODO: name_en ?
  class text,
  brunnel text, -- TODO: only two-value possible
  intermittent integer,
  geom geometry
);


-- create function returning a table_omt_transportation_n_t, WITH name.

--utilities
CREATE OR REPLACE FUNCTION text_to_real_0(text) RETURNS real AS $$
BEGIN
RETURN CAST($1 AS REAL);
  EXCEPTION
  WHEN invalid_text_representation THEN
  RETURN 0.0;
end;
$$ LANGUAGE 'plpgsql' IMMUTABLE;

CREATE OR REPLACE FUNCTION text_to_int_null(text) RETURNS integer AS $$
BEGIN
RETURN CAST($1 AS INTEGER);
  EXCEPTION
  WHEN invalid_text_representation THEN
  RETURN NULL;
end;
$$ LANGUAGE 'plpgsql' IMMUTABLE;


CREATE OR REPLACE FUNCTION public.omt_landuse(bounds_geom geometry,z integer)
RETURNS setof row_omt_landuse
AS $$
BEGIN
RETURN QUERY SELECT
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
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.omt_aeroway(bounds_geom geometry)
RETURNS setof row_omt_aeroway
AS $$
BEGIN
RETURN QUERY
SELECT ref,aeroway AS class,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE aeroway IS NOT NULL AND ST_Intersects(way,bounds_geom);
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;


CREATE OR REPLACE FUNCTION public.omt_landcover(bounds_geom geometry,z integer)
RETURNS setof row_omt_landcover
AS $$
BEGIN
RETURN QUERY
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
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;



CREATE OR REPLACE FUNCTION public.omt_building(bounds_geom geometry,z integer)
RETURNS setof row_omt_building
AS $$
BEGIN
  RETURN QUERY
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
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;


CREATE OR REPLACE FUNCTION public.omt_park(bounds_geom geometry)
RETURNS setof row_omt_park
AS $$
BEGIN
  RETURN QUERY
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
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;


CREATE OR REPLACE FUNCTION public.omt_boundary(bounds_geom geometry, z integer)
RETURNS setof row_omt_boundary
AS $$
BEGIN
  RETURN QUERY
SELECT admin_level::integer AS admin_level,
  tags->'left:country' AS adm0_l,tags->'right:country' AS adm0_r,
  0 AS disputed,
  (CASE admin_level WHEN '2' THEN
    COALESCE(tags->'ISO3166-1:alpha2',tags->'ISO3166-1',tags->'country_code_fips')
    ELSE NULL END) AS claimed_by,
  (CASE boundary WHEN 'maritime' THEN 1 ELSE 0 END) AS maritime,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_line
WHERE (boundary IN ('administrative') OR CASE
    WHEN z<=4 THEN boundary IN ('maritime')
      AND admin_level IN ('1','2') ELSE false
    END)
   AND (z>=11 OR admin_level IN ('1','2','3','4','5','6','7'))
   AND (z>=8 OR admin_level IN ('1','2','3','4'))
   AND (z>=2 OR admin_level IN ('1','2','3'))
   AND ST_Intersects(way,bounds_geom);
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.omt_housenumber(bounds_geom geometry)
RETURNS setof row_omt_housenumber
AS $$
BEGIN
  RETURN QUERY
SELECT "addr:housenumber" AS housenumber,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_line
WHERE "addr:housenumber" IS NOT NULL AND ST_Intersects(way,bounds_geom)
UNION
SELECT "addr:housenumber" AS housenumber,
  ST_AsMVTGeom(ST_Centroid(way),bounds_geom) AS geom
FROM planet_osm_polygon
  -- obviously don't scan on the ST_Centroid(way) because those are not indexed
WHERE "addr:housenumber" IS NOT NULL AND ST_Intersects(way,bounds_geom);
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;


CREATE OR REPLACE FUNCTION public.omt_transportation(bounds_geom geometry,z integer)
RETURNS setof row_omt_named_transportation
AS $$
BEGIN
  RETURN QUERY
    SELECT * FROM public.line_omt_transportation(bounds_geom,z);
    -- add UNION poly_omt_transportation(
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.line_omt_transportation(bounds_geom geometry,z integer)
RETURNS setof row_omt_named_transportation
AS $$
BEGIN
RETURN QUERY SELECT 
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
      THEN substr(highway,-5)
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
  END) AS cycleway, --NOTE: extension
  layer,
  tags->'level' AS level,
  (CASE WHEN tags->'indoor' IN ('yes','1') THEN 1 END) AS indoor,
  -- DO THE ZOOM modulation!
  -- https://github.com/openmaptiles/openmaptiles/blob/master/layers/transportation/transportation.sql
  -- also CHECK tracktypes! in style they look like asphalt roads
  NULLIF(bicycle,'') AS bicycle,
  NULLIF(foot,'') AS foot,
  NULLIF(horse,'') AS horse,
  NULLIF(tags->'mtb:scale','') AS mtb_scale,
  (CASE WHEN surface IN ('paved','asphalt','cobblestone','concrete',
      'concrete:lanes','concrete:plates','metal','paving_stones','sett',
      'unhewn_cobblestone','wood') THEN 'paved'
    WHEN surface IN ('unpaved','compacted','dirt','earth','fine_gravel',
      'grass','grass_paver','grass_paved','gravel','gravel_turf','ground',
      'ice','mud','pebblestone','salt','sand','snow','woodchips') THEN 'unpaved'
  END) AS surface,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_line
WHERE (
  railway IN ('rail','narrow_gauge','preserved','funicular','subway','light_rail',
    'monorail','tram')
  OR highway IN ('motorway','motorway_link','trunk','trunk_link','primary','primary_link',
    'pedestrian','bridleway','corridor','service','track','raceway','busway',
    'bus_guideway','construction')
  OR (highway IN ('path','footway','cycleway','steps') AND z>=13) -- hide paths at lowzoom
  OR (highway IN ('unclassified','residential','living_street') AND z>=12) -- hide minorroads
  OR (highway IN ('tertiary','tertiary_link','road') AND z>=11)
  OR (highway IN ('secondary','secondary_link') AND z>=9)
  OR aerialway IN ('chair_lift','drag_lift','platter','t-bar','gondola','cable_bar',
    'j-bar','mixed_lift')
  OR route IN ('bicycle') --NOTE:extension
) AND ST_Intersects(way,bounds_geom);
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;



  -- NEED tochange structure to read from point,line and polygon...
  -- from point
  --OR highway IN ('motorway_junction')
  -- from polygon
  --OR highway IN ('path','cycleway','bridleway','footway','corridor','pedestrian','steps')


CREATE OR REPLACE FUNCTION public.omt_waterway(bounds_geom geometry,z integer)
RETURNS setof row_omt_waterway
AS $$
BEGIN
  RETURN QUERY
SELECT name,waterway AS class,
  (CASE
    WHEN bridge IS NOT NULL AND bridge!='no' THEN 'bridge'
    WHEN tunnel IS NOT NULL AND tunnel!='no' THEN 'tunnel'
    WHEN tags->'ford' IS NOT NULL AND (tags->'ford')!='no' THEN 'ford'
  END) AS brunnel,
  (CASE
    WHEN intermittent IN ('yes') THEN 1
    ELSE 0
  END) AS intermittent,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_line
WHERE waterway IN ('stream','river','canal','drain','ditch')
  AND ST_Intersects(way,bounds_geom);
    --TODO: by-zoom specificities
    -- TODO: error with dällikon dorfbach not showing
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.omt_place(bounds_geom geometry)
RETURNS setof row_omt_place
AS $$
BEGIN RETURN QUERY
SELECT name,admin_level::integer AS capital,
  place AS class,
  (tags->'ISO3166-1') AS iso_a2,
  z_order AS rank,
  ST_AsMVTGeom(way,bounds_geom) AS geom
FROM planet_osm_polygon
WHERE place IN ('island')
  AND ST_Intersects(way,bounds_geom)
UNION ALL
SELECT name,admin_level::integer AS capital,
  place AS class,
  (tags->'ISO3166-1') AS iso_a2,
  z_order AS rank,
  ST_AsMVTGeom(way,bounds_geom) AS geom
  -- TODO: fix zürich affoltern not showing
FROM planet_osm_point
WHERE place IN ('continent','','country','state','province','city','town','village',
    'hamlet','subrb','quarter','neighbourhood','isolated_dwelling','island')
  AND ST_Intersects(way,bounds_geom);
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

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

CREATE OR REPLACE FUNCTION public.omt_poi(bounds_geom geometry)
RETURNS setof row_omt_poi
AS $$
BEGIN RETURN QUERY
  -- TODO: weiningen the farm does not show. also check maplibre-basic, osm-bright
  --    and osm-liberty styles
SELECT name,class,subclass,get_poi_class_rank(class) AS rank,agg_stop,level,layer,indoor,geom FROM
(SELECT name,
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
    WHEN subclass IN ('townhall', 'public_building', 'courthouse', 'community_centre')
			THEN 'townhall'
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
	END) AS class,
	subclass,agg_stop,level,layer,indoor,geom
	FROM (SELECT name,
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
			'theatre','toilets','townhall','university','veterinary','waste_basket')
			THEN amenity
		WHEN aerialway IN ('station') THEN aerialway
		END) AS subclass,
		(CASE WHEN
			railway IN ('station') THEN 'railway'
			WHEN aerialway IN ('station') THEN 'aerialway'
		END) AS subclass_helper_key, -- distinguish railway=station and aerialway=station
		0 AS agg_stop, -- TODO: not implemented
		tags->'level' AS level,layer,
		(CASE WHEN tags->'indoor' IN ('yes','1') THEN 1 END) AS indoor,
		ST_AsMVTGeom(way,bounds_geom) AS geom
	FROM planet_osm_point
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
			'theatre','toilets','townhall','university','veterinary','waste_basket')
		OR aerialway IN ('station')
		) AND ST_Intersects(way,bounds_geom)
	UNION ALL
	SELECT name,
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
			'theatre','toilets','townhall','university','veterinary','waste_basket')
			THEN amenity
		WHEN aerialway IN ('station') THEN aerialway
		END) AS subclass,
		(CASE WHEN
			railway IN ('station') THEN 'railway'
			WHEN aerialway IN ('station') THEN 'aerialway'
		END) AS subclass_helper_key, -- distinguish railway=station and aerialway=station
		0 AS agg_stop, -- TODO: not implemented
		tags->'level' AS level,layer,
		(CASE WHEN tags->'indoor' IN ('yes','1') THEN 1 END) AS indoor,
		ST_AsMVTGeom(way,bounds_geom) AS geom
	FROM planet_osm_point
	WHERE (
		waterway IN ('dock') OR building IN ('dormitory')
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
			'theatre','toilets','townhall','university','veterinary','waste_basket')
		OR aerialway IN ('station')
		OR highway IN ('bus_stop')
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
		) AND ST_Intersects(way,bounds_geom)) AS without_rank_without_class) AS without_rank;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;



CREATE OR REPLACE FUNCTION public.omt_water(bounds_geom geometry)
RETURNS setof row_omt_named_water
AS $$
BEGIN
  RETURN QUERY
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
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.omt_all(z integer, x integer, y integer)
RETURNS bytea
AS $$
DECLARE
    result bytea;
    bounds_geom geometry;
BEGIN
    SELECT ST_TileEnvelope(z,x,y) INTO bounds_geom;
    WITH
      premvt_transportation AS (
        SELECT * FROM public.omt_transportation(bounds_geom,z)),
      premvt_aeroway AS(
        SELECT * FROM public.omt_aeroway(bounds_geom)),
      premvt_boundary AS (
        SELECT * FROM public.omt_boundary(bounds_geom,z)),
      premvt_building AS (
        SELECT * FROM public.omt_building(bounds_geom,z)),
      premvt_housenumber AS (
        SELECT * FROM public.omt_housenumber(bounds_geom)),
      premvt_landuse AS (
        SELECT * FROM public.omt_landuse(bounds_geom,z)),
      premvt_landcover AS (
        SELECT * FROM public.omt_landcover(bounds_geom,z)),
      premvt_park AS (
        SELECT *,name AS "name:latin" FROM public.omt_park(bounds_geom)),
      premvt_place AS (
        SELECT *,name AS "name:latin" FROM public.omt_place(bounds_geom)),
      premvt_poi AS (
        SELECT *,name AS "name:latin" FROM public.omt_poi(bounds_geom)),
      premvt_water AS (
        SELECT * FROM public.omt_water(bounds_geom)),
      premvt_waterway AS (
        SELECT *,name AS "name:latin" FROM public.omt_waterway(bounds_geom,z)),
      -- the generated {layer} and {layer}_name:
      premvt_water_noname AS (
        SELECT
          id,class,intermittent,brunnel,geom
        FROM premvt_water
      ),
      premvt_water_name AS (
        SELECT
          name,name AS "name:latin",class,
          -- TODO: WARN! different from water_noname
          intermittent,geom
        FROM premvt_water WHERE name IS NOT NULL
      ),
      premvt_transportation_noname AS (
        SELECT
          network,class,subclass,brunnel,oneway,ramp,service,
          access,toll,expressway,cycleway,level,layer,indoor,bicycle,
          foot,horse,mtb_scale,surface,
          geom
        FROM premvt_transportation
      ),
      premvt_transportation_name AS (
        SELECT
          name,name AS "name:latin",ref,length(ref) AS ref_length,
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


SELECT length(public.omt_all(16,34303,22938));

