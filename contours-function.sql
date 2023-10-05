
--TODO: everywhere add this simplify_if_needed
CREATE OR REPLACE FUNCTION public.simplify_if_needed(way geometry,z integer)
RETURNS geometry AS $$
SELECT (CASE
    WHEN z<= 2 THEN ST_SimplifyPreserveTopology(way,100)
    WHEN z<= 5 THEN ST_SimplifyPreserveTopology(way, 35)
    WHEN z<= 7 THEN ST_SimplifyPreserveTopology(way, 15)
    WHEN z<=12 THEN ST_SimplifyPreserveTopology(way, 10)
    ELSE way
  END);
$$ LANGUAGE SQL STABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION public.contours_vector(z integer, x integer, y integer)
RETURNS bytea
AS $$
WITH
  bounds AS (SELECT ST_Transform(ST_TileEnvelope(z,x,y),4326) AS geom),
  premvt_contours AS (
    SELECT
      height::integer AS height,
      (height::integer)%10=0 AND (height::integer)%50!=0 AS height10,
      (height::integer)%50=0 AND (height::integer)%100!=0 AS height50,
      (height::integer)%100=0 AS height100,
      simplify_if_needed(ST_AsMVTGeom(way,bounds.geom),z) AS geom
    FROM public.contours, bounds
    WHERE ST_Intersects(way,bounds.geom) AND (height::integer)%10=0
      AND (CASE
        WHEN z<14 THEN (height::integer)%50=0
        WHEN z<11 THEN (height::integer)%100=0
        WHEN z<9 THEN false -- remove everything at lowzooms
        ELSE true
      END)
    )
SELECT ST_AsMVT(premvt_contours,'heights') FROM premvt_contours;
$$
LANGUAGE 'sql'
STABLE
PARALLEL SAFE;

SELECT length(public.contours_vector(16,34303,22938));

