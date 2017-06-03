#!/bin/bash -e

OSM_STYLE_XML='';
OSM_DB='gis';

function style_osm_bright() {
  cd /usr/local/share/maps/style
  if [ ! -d 'osm-bright-master' ]; then
    wget https://github.com/mapbox/osm-bright/archive/master.zip
    unzip master.zip;
    mkdir -p osm-bright-master/shp
    rm master.zip
  fi
 
  for shp in 'land-polygons-split-3857' 'simplified-land-polygons-complete-3857'; do
    if [ ! -d "osm-bright-master/shp/${shp}" ]; then
      wget http://data.openstreetmapdata.com/${shp}.zip
      unzip ${shp}.zip;
      mv ${shp}/ osm-bright-master/shp/
      rm ${shp}.zip
      pushd osm-bright-master/shp/${shp}/
        shapeindex *.shp
      popd
    fi
  done
 
  if [ ! -d 'osm-bright-master/shp/ne_10m_populated_places' ]; then
    wget http://www.naturalearthdata.com/http//www.naturalearthdata.com/download/10m/cultural/ne_10m_populated_places.zip
    unzip ne_10m_populated_places.zip
    mkdir -p osm-bright-master/shp/ne_10m_populated_places
    rm ne_10m_populated_places.zip
    mv ne_10m_populated_places.* osm-bright-master/shp/ne_10m_populated_places/
  fi
  
  # Configuring OSM Bright
  if [ $(grep -c '.zip' /usr/local/share/maps/style/osm-bright-master/osm-bright/osm-bright.osm2pgsql.mml) -ne 0 ]; then  #if we have zip in mml
    cd /usr/local/share/maps/style/osm-bright-master
    cp osm-bright/osm-bright.osm2pgsql.mml osm-bright/osm-bright.osm2pgsql.mml.orig
    sed -i.save 's|.*simplified-land-polygons-complete-3857.zip",|"file":"/usr/local/share/maps/style/osm-bright-master/shp/simplified-land-polygons-complete-3857/simplified_land_polygons.shp",\n"type": "shape",|' osm-bright/osm-bright.osm2pgsql.mml
    sed -i.save 's|.*land-polygons-split-3857.zip"|"file":"/usr/local/share/maps/style/osm-bright-master/shp/land-polygons-split-3857/land_polygons.shp",\n"type":"shape"|' osm-bright/osm-bright.osm2pgsql.mml
    sed -i.save 's|.*10m-populated-places-simple.zip"|"file":"/usr/local/share/maps/style/osm-bright-master/shp/ne_10m_populated_places/ne_10m_populated_places.shp",\n"type": "shape"|' osm-bright/osm-bright.osm2pgsql.mml
 
    sed -i.save '/name":[ \t]*"ne_places"/a"srs": "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"' osm-bright/osm-bright.osm2pgsql.mml
    
    LINE_FROM=$(grep -n '"srs": "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"' osm-bright/osm-bright.osm2pgsql.mml | cut -f1 -d':')
    let LINE_FROM=LINE_FROM+1
    let LINE_TO=LINE_FROM+1
    sed -i.save "${LINE_FROM},${LINE_TO}d" osm-bright/osm-bright.osm2pgsql.mml
  fi
 
  # Compiling the stylesheet
  if [ ! -f /usr/local/share/maps/style/osm-bright-master/OSMBright/OSMBright.xml ]; then
    cd /usr/local/share/maps/style/osm-bright-master
    cp configure.py.sample configure.py
    sed -i.save 's|config\["path"\].*|config\["path"\] = path.expanduser("/usr/local/share/maps/style")|' configure.py
    sed -i.save "s|config\[\"postgis\"\]\[\"dbname\"\].*|config\[\"postgis\"\]\[\"dbname\"\]=\"${OSM_DB}\"|" configure.py
    ./configure.py
    ./make.py
    cd ../OSMBright/
    carto project.mml > OSMBright.xml
  fi
  OSM_STYLE_XML='/usr/local/share/maps/style/OSMBright/OSMBright.xml'
}

function install_npm_carto() {
  apt-get -y install npm nodejs nodejs-legacy
  # Latest 0.17.2 doesn't install!
  npm install -g carto@0.16.3
  ln -sf /usr/local/lib/node_modules/carto/bin/carto /usr/local/bin/carto
}

# 1 Install Stylesheet
install_npm_carto;
mkdir -p /usr/local/share/maps/style
style_osm_bright;

# 2 Set up webserver
sed -i.save "s|^XML=.*|XML=${OSM_STYLE_XML}|" /usr/local/etc/renderd.conf

systemctl restart renderd

echo <<EOF
OSM stylesheet install done.
EOF
