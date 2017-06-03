#!/bin/bash -e

# bbox=8.0804,47.1281,9.0335,47.6293 Zürich
wget http://download.geofabrik.de/europe/switzerland-latest.osm.pbf
osmconvert switzerland-latest.osm.pbf --out-o5m -o=switzerland-latest.osm.o5m
osmconvert switzerland-latest.osm.o5m -b=8.0804,47.1281,9.0335,47.6293 --complete-ways -o=switzerland-cropped.osm.o5m
osmconvert switzerland-cropped.osm.o5m --out-pbf -o=zurich-data.osm.pbf

echo <<EOF
Test data ready.
EOF
