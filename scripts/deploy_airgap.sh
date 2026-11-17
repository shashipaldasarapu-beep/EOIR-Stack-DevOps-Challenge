#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# EOIR STACK - OFFLINE AIR-GAP DEPLOYMENT
# Release: 1.4.2
# ==========================================================

RELEASE_DIR="${1:-airgap_release}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/eoir-stack}"
HOST_PORT="${HOST_PORT:-8000}"

echo "=================================================="
echo "       EOIR STACK AIR-GAP DEPLOYMENT"
echo "=================================================="

# 1. Resolve release directory
if [[ ! -d "$RELEASE_DIR" ]]; then
    echo "ERROR: Release directory not found: $RELEASE_DIR"
    exit 1
fi

RELEASE_DIR="$(realpath "$RELEASE_DIR")"

# 2. Validate Docker
echo "==> Checking Docker installation"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running."
    exit 1
fi

# 3. Validate release files
echo "==> Checking release files"

REQUIRED_FILES=(
    "SHA256SUMS"
    "images/docker-images.tar"
    "deployment/docker-compose.yml"
    "deployment/.env.example"
    "models/eo_detector_fp16.engine"
    "models/manifest.json"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$RELEASE_DIR/$file" ]]; then
        echo "ERROR: Missing release file: $file"
        exit 1
    fi
done

# 4. Verify checksums before using release contents
echo "==> Verifying SHA256 checksums"

(
    cd "$RELEASE_DIR"
    sha256sum --check SHA256SUMS
)

echo "==> All release checksums verified."

# 5. Prepare deployment directory
echo "==> Preparing deployment directory"

mkdir -p "$DEPLOY_DIR"

cp -r "$RELEASE_DIR/deployment/." "$DEPLOY_DIR/"
cp -r "$RELEASE_DIR/models" "$DEPLOY_DIR/"

# 6. Validate environment configuration
echo "==> Checking environment configuration"

if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
    echo "ERROR: .env file is missing."
    echo "Create it using:"
    echo "cp \"$DEPLOY_DIR/.env.example\" \"$DEPLOY_DIR/.env\""
    exit 1
fi

set -a
source "$DEPLOY_DIR/.env"
set +a

for variable in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB; do
    if [[ -z "${!variable:-}" ]]; then
        echo "ERROR: $variable is missing or empty."
        exit 1
    fi
done

if [[ "$POSTGRES_PASSWORD" == "replace_with_a_strong_random_password" ]]; then
    echo "ERROR: Replace the example PostgreSQL password."
    exit 1
fi

# 7. Validate host port
if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]] ||
   (( HOST_PORT < 1 || HOST_PORT > 65535 )); then
    echo "ERROR: Invalid HOST_PORT: $HOST_PORT"
    exit 1
fi

# 8. Configure host port without changing container port
echo "==> Configuring API host port: $HOST_PORT"

python3 - "$DEPLOY_DIR/docker-compose.yml" "$HOST_PORT" <<'PY'
import sys
from pathlib import Path

compose_file = Path(sys.argv[1])
host_port = sys.argv[2]

content = compose_file.read_text()

old = '"8000:8000"'
new = f'"{host_port}:8000"'

if old in content:
    content = content.replace(old, new)
else:
    import re
    pattern = r"""(['"])8000:8000\1"""
    content, count = re.subn(pattern, lambda _: new, content)

    if count == 0 and f'"{host_port}:8000"' not in content:
        raise SystemExit("ERROR: Could not locate API port mapping.")

compose_file.write_text(content)
print(f"API port configured: {host_port}:8000")
PY

# 9. Validate Compose configuration
echo "==> Validating Docker Compose configuration"

cd "$DEPLOY_DIR"

docker compose config -q

# 10. Load packaged Docker images
echo "==> Loading offline Docker images"

docker load -i "$RELEASE_DIR/images/docker-images.tar"

# 11. Start services without build or internet access
echo "==> Starting EOIR Stack services"

docker compose up -d --no-build --pull never

# 12. Display deployment status
echo "==> Deployment status"

docker compose ps

echo "=================================================="
echo "       AIR-GAP DEPLOYMENT COMPLETED"
echo "=================================================="
echo "Deployment directory: $DEPLOY_DIR"
echo "API endpoint: http://localhost:$HOST_PORT"
echo "Health endpoint: http://localhost:$HOST_PORT/health"
echo "=================================================="
