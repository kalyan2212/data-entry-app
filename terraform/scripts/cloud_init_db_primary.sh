#!/bin/bash
# cloud_init_db_primary.sh
# Runs on first boot of the DB primary VM.
# Installs PostgreSQL 15, creates the database/users,
# and configures streaming replication for the replica.

set -euo pipefail
exec > /var/log/cloud_init_db_primary.log 2>&1

echo "=== [1/4] Install PostgreSQL ==="
apt-get update -y
apt-get install -y postgresql postgresql-contrib

PG_VERSION=$(pg_lsclusters --no-header | awk '{print $1; exit}')
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

echo "PostgreSQL version: $PG_VERSION"

echo "=== [2/4] Configure postgresql.conf for replication ==="
cat >> "$PG_CONF" <<'EOF'

# ── Replication settings added by cloud-init ──────────────────────────────────
listen_addresses = '*'
wal_level = replica
max_wal_senders = 5
wal_keep_size = 256
hot_standby = on
EOF

echo "=== [3/4] Configure pg_hba.conf to allow app VMs and replica ==="
cat >> "$PG_HBA" <<EOF

# App VMs (10.0.1.0/24) → customers DB as appuser
host    customers    appuser      10.0.1.0/24     scram-sha-256

# Replica VM → replication slot
host    replication  replicator   ${replica_ip}/32  scram-sha-256
EOF

systemctl restart postgresql

echo "=== [4/4] Create database, application user, and replication user ==="
sudo -u postgres psql <<SQL
CREATE USER appuser WITH PASSWORD '${db_password}';
CREATE DATABASE customers OWNER appuser;
GRANT ALL PRIVILEGES ON DATABASE customers TO appuser;
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${db_password}';
SQL

echo "=== DB Primary bootstrap complete ==="
