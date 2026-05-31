#!/usr/bin/env bash
set -euo pipefail

# configure.sh: build chrome container and configure a local OpenCode project
# Usage: ./configure.sh [OPENCODE_DIR]

OPENCODE_DIR="${1:-$(pwd)}"
IMAGE_NAME="opencode-chrome:local"
CONTAINER_NAME="opencode-chrome"
CONFIG_DIR="${HOME}/.config/opencode-chrome"

echo "Project: $OPENCODE_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "This script requires Docker. Please install Docker and try again." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "This script requires curl. Please install curl and try again." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GHCR_NAMESPACE="${GHCR_NAMESPACE:-$(whoami)}"
# normalize namespace to lowercase (GHCR requires lowercase repo names)
GHCR_NAMESPACE="${GHCR_NAMESPACE,,}"
IMAGE_REF="${IMAGE_REF:-ghcr.io/${GHCR_NAMESPACE}/opencode-chrome:latest}"

if [ "${1:-}" = "--local-build" ] || [ "${LOCAL_BUILD:-0}" = "1" ]; then
  echo "Building Docker image $IMAGE_NAME from $SCRIPT_DIR/Dockerfile..."
  docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
  IMAGE_TO_RUN="$IMAGE_NAME"
else
  echo "Attempting to pull image $IMAGE_REF from GHCR..."
  if docker pull "$IMAGE_REF"; then
    IMAGE_TO_RUN="$IMAGE_REF"
    echo "Pulled $IMAGE_REF"
  else
    echo "Could not pull $IMAGE_REF. To build locally, re-run with --local-build or set GHCR_NAMESPACE to your GitHub org/user." >&2
    exit 1
  fi
fi

if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
  echo "Removing existing container $CONTAINER_NAME..."
  docker rm -f "$CONTAINER_NAME" || true
fi

mkdir -p "$CONFIG_DIR"

echo "Starting container $CONTAINER_NAME using image $IMAGE_TO_RUN..."
docker run -d --name "$CONTAINER_NAME" \
  -e PUID="$(id -u)" -e PGID="$(id -g)" -e TZ="${TZ:-UTC}" \
  -p 9222:9222 -p 3000:3000 -p 3001:3001 \
  -v "$CONFIG_DIR":/config \
  --shm-size="1gb" --restart unless-stopped "$IMAGE_TO_RUN"

echo "Waiting for Chrome DevTools endpoint at http://127.0.0.1:9222/json/version ..."
for i in $(seq 1 30); do
  if curl -sSf http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
    echo "CDP ready"
    break
  fi
  sleep 1
done

if ! curl -sSf http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
  echo "ERROR: CDP endpoint not reachable at http://127.0.0.1:9222" >&2
  docker logs "$CONTAINER_NAME" --tail 200 || true
  exit 1
fi

echo "Ensuring opencode-chrome-devtools is registered in $OPENCODE_DIR/opencode.json..."
if [ -f "$OPENCODE_DIR/opencode.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.plugin | index("opencode-chrome-devtools")' "$OPENCODE_DIR/opencode.json" >/dev/null 2>&1; then
      tmpfile=$(mktemp)
      jq '.plugin += ["opencode-chrome-devtools"]' "$OPENCODE_DIR/opencode.json" > "$tmpfile" && mv "$tmpfile" "$OPENCODE_DIR/opencode.json"
      echo "Added plugin to $OPENCODE_DIR/opencode.json"
    else
      echo "Plugin already present in opencode.json"
    fi
  else
    python3 - <<PYTHON
import json,sys
path = "${OPENCODE_DIR}/opencode.json"
with open(path,'r+') as f:
    data = json.load(f)
    plugins = data.get('plugin', [])
    if 'opencode-chrome-devtools' not in plugins:
        plugins.append('opencode-chrome-devtools')
        data['plugin'] = plugins
        f.seek(0); f.truncate(0); json.dump(data,f,indent=2)
        print('Added plugin to', path)
    else:
        print('Plugin already present in', path)
PYTHON
  fi
else
  cat > "$OPENCODE_DIR/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": ["opencode-chrome-devtools"]
}
EOF
  echo "Created $OPENCODE_DIR/opencode.json"
fi

echo "Writing $OPENCODE_DIR/.env with OPENCODE_BROWSER_URL..."
cat > "$OPENCODE_DIR/.env" <<EOF
OPENCODE_BROWSER_URL=http://127.0.0.1:9222
EOF

echo "Configuration complete."
echo "- Chrome DevTools available: http://127.0.0.1:9222"
echo "- Container name: $CONTAINER_NAME"
echo "- Project configured: $OPENCODE_DIR"
echo "Try: OPENCODE_BROWSER_URL=http://127.0.0.1:9222 npx @different-ai/opencode-browser status"
