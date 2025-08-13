#!/usr/bin/env bash
set -euo pipefail

# n8n auto-install for Ubuntu 22.04/24.04
# Usage examples:
#   install_n8n.sh --domain example.com --email admin@example.com
#   install_n8n.sh --no-domain
# Env override: N8N_DOMAIN, LE_EMAIL, N8N_VERSION, TZ, BACKUP_RETENTION_DAYS

# ===== Parse args =====
N8N_DOMAIN="${N8N_DOMAIN:-}"
LE_EMAIL="${LE_EMAIL:-}"
NONINTERACTIVE=false
NO_DOMAIN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) N8N_DOMAIN="${2:-}"; shift 2;;
    --email)  LE_EMAIL="${2:-}"; shift 2;;
    --no-domain) NO_DOMAIN=true; shift;;
    --non-interactive) NONINTERACTIVE=true; shift;;
    -h|--help)
      echo "Usage: $0 [--domain DOMAIN --email EMAIL] | [--no-domain] [--non-interactive]"
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ "${NO_DOMAIN}" == true ]]; then
  N8N_DOMAIN=""
fi

if [[ -z "${N8N_DOMAIN}" && "${NONINTERACTIVE}" == true && -n "${LE_EMAIL}" ]]; then
  : # ignore email if no domain
fi

if [[ -z "${N8N_DOMAIN}" && "${NONINTERACTIVE}" == false ]]; then
  read -rp "Домен для n8n (Enter если нет): " N8N_DOMAIN || true
fi
if [[ -n "${N8N_DOMAIN}" && -z "${LE_EMAIL}" && "${NONINTERACTIVE}" == false ]]; then
  read -rp "Email для Let's Encrypt: " LE_EMAIL
fi

# ===== Preconditions =====
if ! command -v apt >/dev/null 2>&1; then
  echo "Нужен Debian/Ubuntu с apt." >&2; exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root: sudo -i; затем ./install_n8n.sh" >&2; exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg ufw jq cron openssl

# ===== Docker =====
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# ===== Paths =====
mkdir -p /opt/n8n/{data,db,backups,proxy}
cd /opt/n8n

# ===== Secrets =====
rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }
N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-n8n}"
N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-$(rand)}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand)}"
N8N_VERSION="${N8N_VERSION:-1.64.0}"
TZ="${TZ:-Europe/Moscow}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
GEN_ENCRYPTION_KEY="$(openssl rand -hex 32)"

# ===== Compose files generator =====
gen_compose_with_traefik() {
cat > docker-compose.yml <<'YML'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./db:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    restart: unless-stopped
    depends_on: [db]
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_HOST: db
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_BASIC_AUTH_ACTIVE: ${N8N_BASIC_AUTH_ACTIVE}
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_DIAGNOSTICS_ENABLED: ${N8N_DIAGNOSTICS_ENABLED}
      N8N_SECURE_COOKIE: true
      GENERIC_TIMEZONE: ${TZ}
      N8N_HOST: ${N8N_DOMAIN}
      WEBHOOK_URL: https://${N8N_DOMAIN}/
      N8N_PROTOCOL: https
    volumes:
      - ./data:/home/node/.n8n
    networks: [web, internal]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`${N8N_DOMAIN}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=le"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  traefik:
    image: traefik:v3.1
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.tlschallenge=true"
      - "--certificatesresolvers.le.acme.email=${LE_EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./proxy:/letsencrypt"
    networks: [web]

networks:
  web: {}
  internal: {}
YML
}

gen_compose_local_only() {
cat > docker-compose.yml <<'YML'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./db:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    restart: unless-stopped
    depends_on: [db]
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_HOST: db
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_BASIC_AUTH_ACTIVE: ${N8N_BASIC_AUTH_ACTIVE}
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_DIAGNOSTICS_ENABLED: ${N8N_DIAGNOSTICS_ENABLED}
      N8N_SECURE_COOKIE: false
      GENERIC_TIMEZONE: ${TZ}
      N8N_PROTOCOL: http
    volumes:
      - ./data:/home/node/.n8n
    ports:
      - "127.0.0.1:5678:5678"
    networks: [internal]

networks:
  internal: {}
YML
}

# ===== .env =====
cat > .env <<EOF
# n8n
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
N8N_ENCRYPTION_KEY=${GEN_ENCRYPTION_KEY}
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION=${N8N_VERSION}

# Postgres
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Domain/TLS
N8N_DOMAIN=${N8N_DOMAIN}
LE_EMAIL=${LE_EMAIL}

# Timezone
TZ=${TZ}
EOF

# ===== Compose variant =====
if [[ -n "${N8N_DOMAIN}" ]]; then
  gen_compose_with_traefik
else
  gen_compose_local_only
fi

# ===== Firewall =====
ufw --force enable || true
ufw allow 22/tcp
if [[ -n "${N8N_DOMAIN}" ]]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

# ===== Backups =====
cat >/usr/local/bin/n8n_pg_backup.sh <<'BKP'
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%F_%H-%M-%S)
docker compose -f /opt/n8n/docker-compose.yml exec -T db \
  pg_dump -U n8n -d n8n | gzip > /opt/n8n/backups/pg_${TS}.sql.gz
find /opt/n8n/backups -type f -name "pg_*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete
BKP
chmod +x /usr/local/bin/n8n_pg_backup.sh
( crontab -l 2>/dev/null; echo "17 2 * * * BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS} /usr/local/bin/n8n_pg_backup.sh" ) | crontab -

# ===== Start =====
docker compose pull
docker compose up -d

echo
echo "==== n8n установлен ===="
if [[ -n "${N8N_DOMAIN}" ]]; then
  echo "URL: https://${N8N_DOMAIN}"
  echo "Basic Auth: ${N8N_BASIC_AUTH_USER} / ${N8N_BASIC_AUTH_PASSWORD}"
else
  echo "Без домена. Доступ локально на сервере: http://127.0.0.1:5678"
  echo "SSH-туннель с ПК:"
  echo "  ssh -N -L 5678:127.0.0.1:5678 root@<SERVER_IP>"
  echo "Затем открой: http://127.0.0.1:5678"
  echo "Basic Auth: ${N8N_BASIC_AUTH_USER} / ${N8N_BASIC_AUTH_PASSWORD}"
  echo
  echo "Добавить домен позже:"
  echo "  1) A-запись домена -> IP сервера"
  echo "  2) Запуск: /opt/n8n$ bash <(curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install_n8n.sh) --domain your.domain --email you@example.com --non-interactive"
fi

