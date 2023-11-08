
DROP TABLE IF EXISTS lake_centerline;
CREATE TABLE {{lake_table_name}}(osm_id bigint PRIMARY KEY, way geometry NOT NULL);

WITH a(a) AS (
  SELECT jsonb_array_elements(('{{input_json}}'::jsonb)->'features'))
INSERT INTO {{lake_table_name}}
SELECT (a.a->'properties'->'OSM_ID')::bigint,ST_Transform(
  ST_SetSRID(ST_GeomFromGeoJSON(a.a->'geometry'),4326),3857)
FROM a;

CREATE INDEX {{lake_table_name}}_idx ON {{lake_table_name}}(osm_id);

SELECT COUNT(*) FROM {{lake_table_name}};
