#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="${1:-airgap_release}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/eoir-stack}"

echo "==> Starting offline deployment"

if [[ ! -d "$RELEASE_DIR" ]]; then
    echo "ERROR: Release directory not found: $RELEASE_DIR"
    exit 1
fi

cd "$RELEASE_DIR"

if [[ ! -f SHA256SUMS ]]; then
    echo "ERROR: SHA256SUMS is missing"
    exit 1
fi

echo "==> Verifying release checksums"
sha256sum --check SHA256SUMS

echo "==> Loading Docker images"
docker load -i images/docker-images.tar

echo "==> Preparing deployment directory"
mkdir -p "$DEPLOY_DIR"
cp -r deployment/. "$DEPLOY_DIR/"
cp -r models "$DEPLOY_DIR/"

cd "$DEPLOY_DIR"

if [[ ! -f .env ]]; then
    echo "ERROR: Create a secure .env file before deployment."
    echo "Copy .env.example to .env and configure a strong password."
    exit 1
fi

echo "==> Starting services without pulling images"
docker compose up -d --no-build --pull never

echo "==> Deployment status"
docker compose ps

echo "==> Air-gap deployment completed"
