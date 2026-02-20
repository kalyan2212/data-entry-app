#!/bin/bash
# cloud_init_db_replica.sh
# Runs on first boot of the DB replica VM.
# Installs PostgreSQL 15, then runs pg_basebackup from the primary
# to set up a hot-standby streaming replica.

set -euo pipefail
exec > /var/log/cloud_init_db_replica.log 2>&1

echo "=== [1/4] Install PostgreSQL ==="
apt-get update -y
apt-get install -y postgresql postgresql-contrib

PG_VERSION=$(pg_lsclusters --no-header | awk '{print $1; exit}')
PG_DATA="/var/lib/postgresql/$PG_VERSION/main"
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

echo "PostgreSQL version: $PG_VERSION"

echo "=== [2/4] Wait for primary to accept replication connections ==="
for i in $(seq 1 36); do
  if PGPASSWORD="${db_password}" pg_isready -h "${primary_ip}" -p 5432 -U replicator 2>/dev/null; then
    echo "Primary is ready after attempt $i"
    break
  fi
  echo "Waiting for primary... attempt $i/36 (10s interval)"
  sleep 10
done

echo "=== [3/4] Take base backup from primary ==="
systemctl stop postgresql
rm -rf "$PG_DATA"/*

PGPASSWORD="${db_password}" pg_basebackup \
  -h "${primary_ip}" \
  -U replicator \
  -D "$PG_DATA" \
  -P \
  --wal-method=stream \
  --checkpoint=fast

echo "=== [4/4] Configure as hot standby ==="
# Add hot_standby and primary_conninfo
cat >> "$PG_CONF" <<EOF

# ── Standby settings added by cloud-init ─────────────────────────────────────
hot_standby = on
listen_addresses = '*'
primary_conninfo = 'host=${primary_ip} port=5432 user=replicator password=${db_password}'
EOF

# Create standby.signal so PostgreSQL starts in standby mode
touch "$PG_DATA/standby.signal"

# Fix ownership after pg_basebackup
chown -R postgres:postgres "$PG_DATA"
chmod 700 "$PG_DATA"

systemctl start postgresql
systemctl enable postgresql

echo "=== DB Replica bootstrap complete – streaming from ${primary_ip} ==="
