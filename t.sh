#!/usr/bin/env bash
# N4 CloudRun — uzinn/n4gcp (US only) → Trojan URL (+5h END time in label)
set -euo pipefail

: "${TELEGRAM_TOKEN:?Set TELEGRAM_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID}"

IMAGE="docker.io/uzinn/n4gcp"
REGION="us-central1"
SERVICE="${SERVICE:-n4gcp-$(date +%s)}"
CPU="2"
MEMORY="2Gi"
TIMEOUT="3600"
PORT="8080"
MIN_INSTANCES="1"
MAX_INSTANCES="5"

TROJAN_PASSWORD="${TROJAN_PASSWORD:-Nanda}"
WS_PATH="${WS_PATH:-/Nanda}"   # leading slash

command -v gcloud >/dev/null || { echo "❌ gcloud not found"; exit 1; }
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT" ]] || { echo "❌ No active project. Use: gcloud config set project <ID>"; exit 1; }

# --- Compute END time (+5h) in Asia/Yangon, AM/PM (e.g. 5:15PM)
if TZ=Asia/Yangon date +%Y >/dev/null 2>&1; then
  END_AMPM="$(TZ=Asia/Yangon date -d '+5 hours' '+%I:%M%p' | sed 's/^0//')"
else
  END_AMPM="$(date -u -d '+5 hours' '+%I:%M%p' | sed 's/^0//')"
fi
LABEL_PLAIN="N4 Trojan(${END_AMPM}- END)"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port "$PORT" \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --timeout "$TIMEOUT" \
  --min-instances "$MIN_INSTANCES" \
  --max-instances "$MAX_INSTANCES" \
  --execution-environment gen2 \
  --set-env-vars "TROJAN_PASSWORD=${TROJAN_PASSWORD}" \
  --set-env-vars "WS_PATH=${WS_PATH}" \
  --quiet

RUN_URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
HOST="${RUN_URL#https://}"

# Encode WS path + label
WS_PATH_ENC="$(python3 - <<'PY'
import os, urllib.parse
print(urllib.parse.quote(os.getenv("WS_PATH","/Nanda"), safe=""))
PY
)"
LABEL_ENC="$(python3 - <<PY
from urllib.parse import quote
print(quote("${LABEL_PLAIN}"))
PY
)"

TROJAN_URL="trojan://${TROJAN_PASSWORD}@vpn.googleapis.com:443?path=${WS_PATH_ENC}&security=tls&host=${HOST}&type=ws&sni=${HOST}#${LABEL_ENC}"

# Send to Telegram (URL line only)
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${TROJAN_URL}" \
  -d disable_web_page_preview=true >/dev/null

# Local echo (optional)
echo "$TROJAN_URL"
