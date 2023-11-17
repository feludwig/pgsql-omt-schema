#!/bin/bash

# inspired from https://github.com/openmaptiles/openmaptiles-tools/blob/master/docker/import-data/clean-natural-earth.sh
# no need for docker if you install these dependencies: ogr2ogr, sqlite3, wget

db_access="${1}"

zip_file="$(echo "natural_earth_vector"*".zip")"
if ! [ -f "${zip_file}" ];then
  echo 'Downloading...'
  wget 'https://dev.maptiler.download/geodata/omt/natural_earth_vector.sqlite_v5.1.2.zip'
fi

ne_file="$(echo "natural_earth_vector"*"/packages/natural_earth_vector.sqlite")"
if ! [ -f "${ne_file}" ];then
  unzip "natural_earth_vector.sqlite_v5.1.2.zip"
  ne_file="$(echo "natural_earth_vector"*"/packages/natural_earth_vector.sqlite")"
else
  echo "Detected NaturalEarth data '${ne_file}'"
fi

if true;then
echo 'Dropping unneeded tables'
{
  sqlite3 "${ne_file}" << EOF
SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN (
  'ne_110m_admin_0_boundary_lines_land',
  'ne_50m_admin_0_boundary_lines_land',
  'ne_10m_admin_0_boundary_lines_land',
  'ne_50m_admin_1_states_provinces_lines',
  'ne_10m_admin_1_states_provinces_lines',
  'ne_110m_ocean',
  'ne_50m_ocean',
  'ne_10m_ocean',
  'ne_10m_admin_0_boundary_lines_maritime_indicator',
  'ne_110m_admin_0_pacific_groupings',
  'ne_10m_admin_0_disputed_areas',
-- sqlite internal
  'sqlite_sequence',
-- ogr2ogr relies on these
  'geometry_columns',
  'spatial_ref_sys'
);
EOF
} |while read l;do
  sqlite3 "${ne_file}" << EOF
DROP TABLE ${l};
DELETE FROM geometry_columns WHERE f_table_name='${l}';
EOF
  printf '.'
done

echo ' Vacuuming...'
#makes size smaller
sqlite3 "${ne_file}" <<< 'vacuum;'
fi

echo "Importing data to '${db_access}'"

ogr2ogr -progress -f Postgresql -s_srs EPSG:4326 -t_srs EPSG:3857 \
  -clipsrc -180.1 -85.0511 180.1 85.0511 "PG:${db_access}" \
  -lco GEOMETRY_NAME=way -lco OVERWRITE=YES -lco GEOM_TYPE=geometry \
  -lco DIM=2 -nlt GEOMETRY -overwrite "${ne_file}"
