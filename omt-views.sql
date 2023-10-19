

CREATE MATERIALIZED VIEW IF NOT EXISTS {{omt_view_pref}}_country_boundaries AS
  SELECT {{polygon.name_v}} AS p_name,
    {{polygon.osm_id_v}} AS p_osm_id,
    ST_Area(ST_Intersection(ST_Buffer({{line.way_v}},10,'side=left'),{{polygon.way_v}})) AS leftarea,
    ST_Area(ST_Intersection(ST_Buffer({{line.way_v}},10,'side=right'),{{polygon.way_v}})) AS rightarea,
    {{line.table_name}}.*
  FROM {{polygon.table_name}},{{line.table_name}}
  WHERE {{line.admin_level_v}} IS NOT NULL AND {{line.admin_level_v}} IN ('1','2')
    AND {{polygon.admin_level_v}}={{line.admin_level_v}}
    AND ST_Intersects({{polygon.way_v}},{{line.way_v}});
