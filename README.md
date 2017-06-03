# Welcome

The scripts in this repository can be used to build a map tile server

## Getting started

Install Ubuntu 16.10 on a server

* allow 4 or 8 GB swap space - you'll need it

Download a copy of this repository

```
# apt-get -y install wget unzip
# wget https://github.com/tomedme/tile-server/archive/master.zip
# unzip master.zip
# cd tile-server-master/
# chmod +x *.sh
```
Go through the scripts in order, from 0

* step 3 will take a while - use screen!

## Separate servers for database and tile rendering

You can install the database and the rendering parts on separate servers

Allow remote login in PostgreSQL:

/etc/postgresql/9.5/main/pg_hba.conf:
```
host all all 0.0.0.0/0 trust
```
/etc/postgresql/9.5/main/postgresql.conf:
```
listen_addresses='*'
```

## Credits

Scripts inspired by/modified from [Open Tile Server](https://opentileserver.org/)