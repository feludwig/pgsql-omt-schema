
DROP TABLE IF EXISTS {{lake_table_name}};
CREATE TABLE {{lake_table_name}}(osm_id bigint PRIMARY KEY, way geometry NOT NULL);

WITH a(a) AS (
  SELECT jsonb_array_elements(('{{input_json}}'::jsonb)->'features'))
INSERT INTO {{lake_table_name}}
SELECT (a.a->'properties'->'OSM_ID')::bigint,ST_Transform(
    --project from latlon (srid:4326) to mercator meters (srid:3857)
  ST_SetSRID(ST_GeomFromGeoJSON(a.a->'geometry'),4326),3857)
FROM a;

CREATE INDEX {{lake_table_name}}_idx ON {{lake_table_name}}(osm_id);

SELECT COUNT(*),pg_size_pretty(pg_table_size('{{lake_table_name}}')) AS size FROM {{lake_table_name}};
