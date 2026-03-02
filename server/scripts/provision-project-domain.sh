#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-}"
DOMAIN="${2:-}"

if [[ -z "$PROJECT_NAME" ]]; then
  echo "usage: $0 <project-name> [domain]" >&2
  exit 1
fi

ROOT="/var/www/aiir"
RUNTIME_HOST="${AI_RUNTIME_HOST:-127.0.0.1}"
RUNTIME_PORT="${AI_RUNTIME_PORT:-7788}"
API_BASE="http://${RUNTIME_HOST}:${RUNTIME_PORT}"

APPLY_SYSTEM="${AIIR_PROVISION_APPLY:-0}"
DB_PROFILE="${AIIR_DB_DEFAULT_PROFILE:-default}"
REGION="${AIIR_DB_REGION:-local}"
RETENTION_DAYS="${AIIR_DB_RETENTION_DAYS:-30}"

GEN_DIR="${ROOT}/server/generated"
ENV_DIR="${ROOT}/server/env/projects"
POLICY_DIR="${ROOT}/ai/state/projects"
mkdir -p "$GEN_DIR" "$ENV_DIR" "$POLICY_DIR"

IDEMPOTENCY_KEY="prov-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

PAYLOAD_FILE="${TMPDIR}/create.json"
cat > "$PAYLOAD_FILE" <<EOF
{"project_name":"${PROJECT_NAME}","db_profile":"${DB_PROFILE}","region":"${REGION}","retention_days":${RETENTION_DAYS},"idempotency_key":"${IDEMPOTENCY_KEY}"}
EOF

HTTP_CODE="$(curl -sS -o "${TMPDIR}/create-resp.json" -w "%{http_code}" \
  -X POST "${API_BASE}/aiir/project/create" \
  -H "Content-Type: application/json" \
  --data-binary "@${PAYLOAD_FILE}")"

if [[ "$HTTP_CODE" != "202" ]]; then
  echo "project create failed: http=${HTTP_CODE}" >&2
  cat "${TMPDIR}/create-resp.json" >&2 || true
  exit 1
fi

RESP="$(cat "${TMPDIR}/create-resp.json")"
PROJECT_REF="$(printf '%s' "$RESP" | sed -n 's/.*"project_ref":"\([^"]*\)".*/\1/p' | head -n1)"
DB_REF="$(printf '%s' "$RESP" | sed -n 's/.*"db_ref":"\([^"]*\)".*/\1/p' | head -n1)"
STATUS="$(printf '%s' "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -n1)"
EVENTS_CHANNEL="$(printf '%s' "$RESP" | sed -n 's/.*"events_channel":"\([^"]*\)".*/\1/p' | head -n1)"

if [[ -z "$PROJECT_REF" || -z "$DB_REF" ]]; then
  echo "invalid gateway response" >&2
  cat "${TMPDIR}/create-resp.json" >&2
  exit 1
fi

PROJECT_ENV_FILE="${ENV_DIR}/${PROJECT_REF}.env"
cat > "$PROJECT_ENV_FILE" <<EOF
PROJECT_NAME=${PROJECT_NAME}
PROJECT_REF=${PROJECT_REF}
DB_REF=${DB_REF}
PROJECT_DOMAIN=${DOMAIN}
AIIR_HUMAN_DB_MODE=indirect
AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0
AI_POLICY_ALLOW_DB_EXEC=0
AI_POLICY_ALLOW_OPS=
AI_CAP_REQUIRE=1
AI_LOG_REQUESTS=1
EOF

PROJECT_POLICY_DIR="${POLICY_DIR}/${PROJECT_REF}"
mkdir -p "$PROJECT_POLICY_DIR"
PROJECT_POLICY_FILE="${PROJECT_POLICY_DIR}/policy.env"
cat > "$PROJECT_POLICY_FILE" <<EOF
PROJECT_REF=${PROJECT_REF}
DB_REF=${DB_REF}
AIIR_POLICY_MODE=deny-by-default
AI_POLICY_ALLOW_DB_EXEC=0
AI_POLICY_ALLOW_OPS=
AI_CAP_REQUIRE=1
AIIR_DB_REQUIRE_CAPABILITY=1
AIIR_DB_ALLOW_DIRECT_CREDENTIALS=0
AIIR_HUMAN_DB_MODE=indirect
EOF

WEBSERVER="none"
CONF_FILE=""
if [[ -n "$DOMAIN" ]]; then
  if command -v nginx >/dev/null 2>&1; then
    WEBSERVER="nginx"
    mkdir -p "${GEN_DIR}/nginx"
    CONF_FILE="${GEN_DIR}/nginx/${PROJECT_REF}.conf"
    cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://${RUNTIME_HOST}:${RUNTIME_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    if [[ "$APPLY_SYSTEM" == "1" && -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]]; then
      cp "$CONF_FILE" "/etc/nginx/sites-available/aiir-${PROJECT_REF}.conf"
      ln -sf "/etc/nginx/sites-available/aiir-${PROJECT_REF}.conf" "/etc/nginx/sites-enabled/aiir-${PROJECT_REF}.conf"
      nginx -t
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload nginx
      fi
    fi
  elif command -v apachectl >/dev/null 2>&1 || command -v apache2ctl >/dev/null 2>&1; then
    WEBSERVER="apache"
    mkdir -p "${GEN_DIR}/apache"
    CONF_FILE="${GEN_DIR}/apache/${PROJECT_REF}.conf"
    cat > "$CONF_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}

    ProxyPreserveHost On
    ProxyPass / http://${RUNTIME_HOST}:${RUNTIME_PORT}/
    ProxyPassReverse / http://${RUNTIME_HOST}:${RUNTIME_PORT}/
</VirtualHost>
EOF
    if [[ "$APPLY_SYSTEM" == "1" && -d /etc/apache2/sites-available ]]; then
      cp "$CONF_FILE" "/etc/apache2/sites-available/aiir-${PROJECT_REF}.conf"
      if command -v a2ensite >/dev/null 2>&1; then
        a2ensite "aiir-${PROJECT_REF}.conf" >/dev/null
      fi
      if command -v apachectl >/dev/null 2>&1; then
        apachectl configtest
      elif command -v apache2ctl >/dev/null 2>&1; then
        apache2ctl configtest
      fi
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload apache2 || systemctl reload httpd || true
      fi
    fi
  fi
fi

cat <<EOF
provision-ok
project_ref=${PROJECT_REF}
db_ref=${DB_REF}
status=${STATUS}
events_channel=${EVENTS_CHANNEL}
project_env=${PROJECT_ENV_FILE}
project_policy=${PROJECT_POLICY_FILE}
webserver=${WEBSERVER}
web_conf=${CONF_FILE}
system_apply=${APPLY_SYSTEM}
EOF
