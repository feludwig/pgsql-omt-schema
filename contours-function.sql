
CREATE OR REPLACE FUNCTION public.contours_vector(z integer, x integer, y integer)
RETURNS bytea
AS $$
WITH
  bounds AS (SELECT ST_Transform(ST_TileEnvelope(z,x,y),4326) AS geom),
  premvt_contours AS (
    SELECT
      height::integer AS height,
      -- %50!=0 implies %100!=0
      (height::integer)%10=0 AND (height::integer)%50!=0 AS height10,
      (height::integer)%50=0 AND (height::integer)%100!=0 AS height50,
      (height::integer)%100=0 AS height100,
      ST_AsMVTGeom(way,bounds.geom) AS geom
    FROM public.contours, bounds
    WHERE ST_Intersects(way,bounds.geom)
      AND (
        (z>=14 AND (height::integer)%10=0)
        OR (11<=z AND z<14 AND (height::integer)%50=0)
        OR (9<=z AND z<11 AND (height::integer)%100=0)
        -- remove everything at lowzooms
      )
  )
SELECT ST_AsMVT(premvt_contours,'heights') FROM premvt_contours;
$$
LANGUAGE 'sql' STABLE PARALLEL SAFE;

SELECT length(public.contours_vector(15,17151,11469));

