#!/bin/bash -e

# User for DB and renderd

OSM_USER='tile'; # system user for renderd and db
OSM_USER_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32);
OSM_PG_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32);
OSM_DB='gis'; # osm database name
VHOST=$(hostname -f);

NP=$(grep -c 'model name' /proc/cpuinfo);
osm2pgsql_OPTS="--slim -d ${OSM_DB} --number-processes ${NP} --hstore";

touch /root/auth.txt

# Steps
# 1 Install needed packages
apt-get -y install \
  git-core tar unzip wget bzip2 \
  build-essential autoconf libtool automake \
  apache2 apache2-dev

# 2 Create system user
if [ $(grep -c ${OSM_USER} /etc/passwd) -eq 0 ]; then # if we don't have the OSM user
  useradd -m ${OSM_USER}
  echo ${OSM_USER}:${OSM_USER_PASS} | chpasswd
  echo "${OSM_USER} pass: ${OSM_USER_PASS}" >> /root/auth.txt
fi

# 3 Install osm2pgsql and mapnik
apt-get install -y osm2pgsql python3-mapnik libmapnik3.0 mapnik-utils libmapnik-dev

# 4 Install modtile and renderd
mkdir -p ~/src
if [ -z "$(which renderd)" ]; then # if mapnik is not installed
  cd ~/src
  git clone git://github.com/openstreetmap/mod_tile.git
  if [ ! -d mod_tile ]; then "Error: Failed to download mod_tile"; exit 1; fi

  cd mod_tile
  
  ./autogen.sh
  ./configure

  # install breaks if dir exists
  if [ -d /var/lib/mod_tile ]; then rm -r /var/lib/mod_tile; fi

  make
  make install
  make install-mod_tile

  ldconfig
  
  cp  debian/renderd.init /etc/init.d/renderd
  # Update daemon config
  sed -i.save 's|^DAEMON=.*|DAEMON=/usr/local/bin/$NAME|' /etc/init.d/renderd
  sed -i.save 's|^DAEMON_ARGS=.*|DAEMON_ARGS="-c /usr/local/etc/renderd.conf"|' /etc/init.d/renderd
  sed -i.save "s|^RUNASUSER=.*|RUNASUSER=${OSM_USER}|" /etc/init.d/renderd

  chmod u+x /etc/init.d/renderd
  ln -sf /etc/init.d/renderd /etc/rc2.d/S20renderd
  mkdir -p /var/run/renderd
  chown ${OSM_USER}:${OSM_USER} /var/run/renderd

  cd ../
  rm -rf mod_tile
fi

# Ignore this one; handled later
OSM_STYLE_XML='';

# 4 Set up webserver
MAPNIK_PLUG=$(mapnik-config --input-plugins);
#remove commented lines, because daemon produces warning!
sed -i.save '/^;/d' /usr/local/etc/renderd.conf
sed -i.save 's/;socketname/socketname/' /usr/local/etc/renderd.conf
sed -i.save "s|^plugins_dir=.*|plugins_dir=${MAPNIK_PLUG}|" /usr/local/etc/renderd.conf
sed -i.save 's|^font_dir=.*|font_dir=/usr/share/fonts/truetype|' /usr/local/etc/renderd.conf
# sed -i.save "s|^XML=.*|XML=${OSM_STYLE_XML}|" /usr/local/etc/renderd.conf
sed -i.save 's|^HOST=.*|HOST=localhost|' /usr/local/etc/renderd.conf

mkdir -p /var/run/renderd
chown ${OSM_USER}:${OSM_USER} /var/run/renderd
mkdir -p /var/lib/mod_tile
chown ${OSM_USER}:${OSM_USER} /var/lib/mod_tile

# 5 Configure mod_tile
if [ ! -f /etc/apache2/conf-available/mod_tile.conf ]; then
  echo 'LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so' > /etc/apache2/conf-available/mod_tile.conf

  echo 'LoadTileConfigFile /usr/local/etc/renderd.conf
ModTileRenderdSocketName /var/run/renderd/renderd.sock
# Timeout before giving up for a tile to be rendered
ModTileRequestTimeout 0
# Timeout before giving up for a tile to be rendered that is otherwise missing
ModTileMissingRequestTimeout 30' > /etc/apache2/sites-available/tile.conf

  sed -i.save "/ServerAdmin/aInclude /etc/apache2/sites-available/tile.conf" /etc/apache2/sites-available/000-default.conf

  a2enconf mod_tile
  service apache2 reload
fi

# Create index.html
rm /var/www/html/index.html
cat >/var/www/html/index.html <<EOF
<html>
<head>
  <title>Map Demo</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css">
  <script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
  <style type="text/css"> html, body, #map { width: 100%; height: 100%; margin: 0; } </style>
</head>
<body >
  <div id="map"></div>
<script>

  // Zürich
  var map = L.map('map').setView([47.37272, 8.53771], 11);

  tileUrl = '/osm_tiles/{z}/{x}/{y}.png';
  
  L.tileLayer(tileUrl, {
    maxZoom: 16,
    attribution: false
  }).addTo(map);
  
  function getTileInfo(lat, lon, zoom) {
    var xtile = parseInt(Math.floor((lon+180)/360*(1<<zoom)));
    var ytile = parseInt(Math.floor((1-Math.log(Math.tan(lat*Math.PI/180)+1/Math.cos(lat*Math.PI/180))/Math.PI)/2*(1<<zoom)));
    return "x: " + xtile + " - y: " + ytile + " - z: " + zoom;
  }

  var popup = L.popup();
  function onMapClick(e) {
    // console.log( e );
    // console.log(getTileURL(e.latlng.lat, e.latlng.lng, map.getZoom()));
    popup
      .setLatLng(e.latlng)
      .setContent(e.latlng.toString() + "<br>" + getTileInfo(e.latlng.lat, e.latlng.lng, map.getZoom()))
      .openOn(map);
  }
  map.on('click', onMapClick);
  
</script>
</body>
</html>
EOF

cat >/etc/apache2/sites-available/000-default.conf <<CMD_EOF
<VirtualHost _default_:80>
  ServerAdmin webmaster@localhost
  Include /etc/apache2/sites-available/tile.conf
  DocumentRoot /var/www/html
  ServerName ${VHOST}

  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CMD_EOF

ln -sf /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-enabled/

ldconfig

# Restart services
systemctl daemon-reload
systemctl restart apache2 renderd

echo <<EOF
OSM Frontend server install done.
Authentication data is in /root/auth.txt
EOF
