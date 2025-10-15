#!/usr/bin/env bash
# N4 — Cloud Run (US only) VLESS gRPC → send URL to Telegram immediately
set -euo pipefail

# ===== Required: Telegram creds =====
: "${TELEGRAM_TOKEN:?Set TELEGRAM_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Set TELEGRAM_CHAT_ID}"

# ===== Fixed Cloud Run config =====
REGION="us-central1"
SERVICE="${SERVICE:-n4vlg-$(date +%s)}"
CPU="2"
MEMORY="2Gi"
TIMEOUT="3600"
CONCURRENCY="100"
MIN_INSTANCES="1"
MAX_INSTANCES="10"
PORT="8080"

# ===== Image & protocol settings =====
# Note: vlessgrpc image
IMAGE="${IMAGE:-docker.io/n4pro/vlessgrpc:latest}"

# Server-side protocol envs (image follows these common names)
VLESS_UUID="${VLESS_UUID:-0c890000-4733-4a0e-9a7f-fc341bd20000}"
GRPC_SERVICE_NAME="${GRPC_SERVICE_NAME:-n4-grpc}"   # client side serviceName

# ===== Preflight =====
command -v gcloud >/dev/null || { echo "❌ gcloud not found"; exit 1; }
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT" ]] || { echo "❌ No active project. Run: gcloud config set project <ID>"; exit 1; }

# ===== Compute END label (+5h, Asia/Yangon) =====
if TZ=Asia/Yangon date +%Y >/dev/null 2>&1; then
  END_AMPM="$(TZ=Asia/Yangon date -d '+5 hours' '+%I:%M%p' | sed 's/^0//')"
else
  END_AMPM="$(date -u -d '+5 hours' '+%I:%M%p' | sed 's/^0//')"
fi
LABEL_PLAIN="VLESS gRPC(${END_AMPM}- END)"

# ===== Enable APIs =====
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# ===== Deploy to Cloud Run (Gen2) =====
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port "$PORT" \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --timeout "$TIMEOUT" \
  --execution-environment gen2 \
  --concurrency "$CONCURRENCY" \
  --min-instances "$MIN_INSTANCES" \
  --max-instances "$MAX_INSTANCES" \
  --set-env-vars "VLESS_UUID=${VLESS_UUID}" \
  --set-env-vars "GRPC_SERVICE_NAME=${GRPC_SERVICE_NAME}" \
  --quiet

# ===== Get URL & build VLESS gRPC URL =====
RUN_URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
HOST="${RUN_URL#https://}"

# URL-encode label
LABEL_ENC="$(python3 - <<PY
from urllib.parse import quote
print(quote("${LABEL_PLAIN}"))
PY
)"

# VLESS gRPC (front via vpn.googleapis.com, SNI = Cloud Run host)
VLESS_URL="vless://${VLESS_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${HOST}#${LABEL_ENC}"

# ===== Send to Telegram (just the URL) =====
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${VLESS_URL}" \
  -d disable_web_page_preview=true >/dev/null

# Local echo (optional)
echo "$VLESS_URL"
