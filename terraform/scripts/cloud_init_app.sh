#!/bin/bash
# cloud_init_app.sh
# Runs on first boot of each app VM.
# Installs Python, Nginx, clones the app, and starts Gunicorn as a systemd service.
# Template variables (db_host, db_port, etc.) are injected by Terraform templatefile().

set -euo pipefail
exec > /var/log/cloud_init_app.log 2>&1

echo "=== [1/8] System update and package install ==="
apt-get update -y
apt-get install -y python3.11 python3.11-venv python3-pip nginx git curl

echo "=== [2/8] Clone repository ==="
mkdir -p /opt/data-entry-app
git clone ${github_repo} /opt/data-entry-app

echo "=== [3/8] Python virtual environment ==="
python3.11 -m venv /opt/data-entry-app/venv
/opt/data-entry-app/venv/bin/pip install --upgrade pip
/opt/data-entry-app/venv/bin/pip install -r /opt/data-entry-app/requirements.txt

echo "=== [4/8] Write environment file ==="
mkdir -p /etc/data-entry-app
cat > /etc/data-entry-app/env <<'ENVEOF'
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
FLASK_SECRET_KEY=${flask_secret_key}
UPSTREAM_API_KEY=${upstream_api_key}
DOWNSTREAM_API_KEY=${downstream_api_key}
ENVEOF
chmod 600 /etc/data-entry-app/env

echo "=== [5/8] Wait for PostgreSQL primary to be available ==="
for i in $(seq 1 36); do
  if /opt/data-entry-app/venv/bin/python3 -c "
import os, psycopg2
psycopg2.connect(
  host='${db_host}', port=${db_port},
  dbname='${db_name}', user='${db_user}',
  password='${db_password}'
).close()
" 2>/dev/null; then
    echo "Database is ready after attempt $i"
    break
  fi
  echo "Waiting for database... attempt $i/36 (10s interval)"
  sleep 10
done

echo "=== [6/8] Initialize database schema ==="
cd /opt/data-entry-app
export DB_HOST="${db_host}" DB_PORT="${db_port}" DB_NAME="${db_name}" \
       DB_USER="${db_user}" DB_PASSWORD="${db_password}" \
       FLASK_SECRET_KEY="${flask_secret_key}"
/opt/data-entry-app/venv/bin/python3 -c "from app import init_db; init_db()"

echo "=== [7/8] Systemd service for Gunicorn ==="
mkdir -p /var/log/data-entry-app
chown -R www-data:www-data /var/log/data-entry-app
chown -R www-data:www-data /opt/data-entry-app

cat > /etc/systemd/system/data-entry-app.service <<'SVCEOF'
[Unit]
Description=Data Entry Flask Application (Gunicorn)
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/data-entry-app
EnvironmentFile=/etc/data-entry-app/env
ExecStart=/opt/data-entry-app/venv/bin/gunicorn \
    --workers 4 \
    --bind 127.0.0.1:5000 \
    --access-logfile /var/log/data-entry-app/access.log \
    --error-logfile /var/log/data-entry-app/error.log \
    app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable data-entry-app
systemctl start data-entry-app

echo "=== [8/8] Nginx reverse proxy ==="
cat > /etc/nginx/sites-available/data-entry-app <<'NGXEOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 90;
    }
}
NGXEOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/data-entry-app /etc/nginx/sites-enabled/
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "=== App VM bootstrap complete ==="
