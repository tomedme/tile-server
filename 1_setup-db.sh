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
  postgresql-contrib postgis postgresql-9.5-postgis-2.2 libpq-dev osmctools

PG_VER=$(pg_config | grep '^VERSION' | cut -f4 -d' ' | cut -f1,2 -d.);

# 2 Create system user
if [ $(grep -c ${OSM_USER} /etc/passwd) -eq 0 ]; then # if we don't have the OSM user
  useradd -m ${OSM_USER}
  echo ${OSM_USER}:${OSM_USER_PASS} | chpasswd
  echo "${OSM_USER} pass: ${OSM_USER_PASS}" >> /root/auth.txt
fi

cat >/etc/postgresql/${PG_VER}/main/pg_hba.conf <<CMD_EOF
local all all trust
host all all 127.0.0.1 255.255.255.255 md5
host all all 0.0.0.0/0 md5
host all all ::1/128 md5
CMD_EOF

service postgresql restart

# 3 Create DB user
if [ $(psql -Upostgres -c "select usename from pg_user" | grep -m 1 -c ${OSM_USER}) -eq 0 ]; then
  psql -Upostgres -c "create user ${OSM_USER} with password '${OSM_PG_PASS}';"
else
  psql -Upostgres -c "alter user ${OSM_USER} with password '${OSM_PG_PASS}';"
fi

echo "${OSM_USER} db pass: ${OSM_PG_PASS}" >> /root/auth.txt

if [ $(psql -Upostgres -c "select datname from pg_database" | grep -m 1 -c ${OSM_DB}) -eq 0 ]; then
  psql -Upostgres -c "create database ${OSM_DB} ENCODING 'UTF8' owner=${OSM_USER};"
fi

psql -Upostgres ${OSM_DB} <<EOF_CMD
\c ${OSM_DB}
CREATE EXTENSION hstore;
CREATE EXTENSION postgis;
ALTER TABLE geometry_columns OWNER TO ${OSM_USER};
ALTER TABLE spatial_ref_sys OWNER TO ${OSM_USER};
EOF_CMD

# 4 Install osm2pgsql and mapnik
apt-get install -y osm2pgsql python3-mapnik libmapnik3.0 mapnik-utils libmapnik-dev
 
# tiles need to have access without password
sed -i 's/local all all.*/local all all trust/'  /etc/postgresql/${PG_VER}/main/pg_hba.conf
 
# Restart services
systemctl daemon-reload
systemctl restart postgresql

echo <<EOF
OSM Database server install done.
Authentication data is in /root/auth.txt
EOF
