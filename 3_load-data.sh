#!/bin/bash -e

# ./3_load-data.sh file.osm.pbf

PBF_FILE="${1}";

# User for DB and renderd
OSM_USER='tile'; # system user for renderd and db
OSM_DB='gis'; # osm database name

NP=$(grep -c 'model name' /proc/cpuinfo)
osm2pgsql_OPTS="-v --slim -d ${OSM_DB} --number-processes ${NP} --hstore"

PG_VER=$(pg_config | grep '^VERSION' | cut -f4 -d' ' | cut -f1,2 -d.)

# 1 Tune the system
sed -i 's/#\?shared_buffers.*/shared_buffers = 128MB/' /etc/postgresql/${PG_VER}/main/postgresql.conf
sed -i 's/#\?checkpoint_segments.*/checkpoint_segments = 20/' /etc/postgresql/${PG_VER}/main/postgresql.conf
sed -i 's/#\?maintenance_work_mem.*/maintenance_work_mem = 256MB/' /etc/postgresql/${PG_VER}/main/postgresql.conf

# Turn off autovacuum and fsync during load of PBF
sed -i 's/#\?fsync.*/fsync = off/' /etc/postgresql/${PG_VER}/main/postgresql.conf
sed -i 's/#\?autovacuum.*/autovacuum = off/' /etc/postgresql/${PG_VER}/main/postgresql.conf

service postgresql restart

if [ $(grep -c 'kernel.shmmax=268435456' /etc/sysctl.conf) -eq 0 ]; then
  echo '# Increase kernel shared memory segments - needed for large databases
kernel.shmmax=268435456' >> /etc/sysctl.conf
  sysctl -w kernel.shmmax=268435456
fi

# 2 Load data into postgresql
cp ${PBF_FILE} /home/${OSM_USER}/${PBF_FILE}
chown ${OSM_USER}:${OSM_USER} /home/${OSM_USER}/${PBF_FILE}
cd /home/${OSM_USER}

# get available memory
let C_MEM=$(free -m | grep -i 'mem:' | sed 's/[ \t]\+/ /g' | cut -f4,7 -d' ' | tr ' ' '+')-200
sudo -u ${OSM_USER} osm2pgsql ${osm2pgsql_OPTS} -C ${C_MEM} ${PBF_FILE}

if [ $? -eq 0 ]; then # If import went good
  rm -rf /home/${OSM_USER}/${PBF_FILE}
fi

# Turn on autovacuum and fsync during load of PBF
sed -i.save 's/#\?fsync.*/fsync = on/' /etc/postgresql/${PG_VER}/main/postgresql.conf
sed -i.save 's/#\?autovacuum.*/autovacuum = on/' /etc/postgresql/${PG_VER}/main/postgresql.conf

# tiles need to have access without password
sed -i 's/local all all.*/local all all trust/'  /etc/postgresql/${PG_VER}/main/pg_hba.conf

# Restart services
systemctl restart postgresql 

echo <<EOF
OSM import done.
EOF
