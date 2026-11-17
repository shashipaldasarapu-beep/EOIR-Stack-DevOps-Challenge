#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.4.2"
IMAGE_NAME="eoir-stack"
RELEASE_DIR="airgap_release"
ARCHIVE="release_v${VERSION}.tar.gz"

echo "==> Preparing air-gap release ${VERSION}"

# Check Docker CLI
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed or unavailable."
    exit 1
fi

# Check Docker daemon
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running."
    exit 1
fi

# Build application image
echo "==> Building application image"
docker compose build

# Verify required images
echo "==> Verifying Docker images"
docker image inspect "${IMAGE_NAME}:${VERSION}" >/dev/null
docker image inspect "postgres:15-alpine" >/dev/null

# Remove previous release
echo "==> Cleaning previous release"
rm -rf "${RELEASE_DIR}"
rm -f "${ARCHIVE}"

# Create release directories
mkdir -p "${RELEASE_DIR}/images"
mkdir -p "${RELEASE_DIR}/models"
mkdir -p "${RELEASE_DIR}/deployment"
mkdir -p "${RELEASE_DIR}/source"

# Export Docker images
echo "==> Exporting Docker images"

docker save \
    "${IMAGE_NAME}:${VERSION}" \
    "postgres:15-alpine" \
    -o "${RELEASE_DIR}/images/docker-images.tar"

# Copy deployment files
echo "==> Copying deployment configuration"

cp docker-compose.yml "${RELEASE_DIR}/deployment/"
cp .env.example "${RELEASE_DIR}/deployment/"

# Copy application source
echo "==> Copying application source"

cp Dockerfile "${RELEASE_DIR}/source/"
cp -r vision_api "${RELEASE_DIR}/source/"
cp -r inference_worker "${RELEASE_DIR}/source/"

# Remove unnecessary Python cache files
echo "==> Removing Python cache files"

find "${RELEASE_DIR}/source" \
    -type d -name "__pycache__" -prune -exec rm -rf {} +

find "${RELEASE_DIR}/source" \
    -type f -name "*.pyc" -delete

# Copy model files
echo "==> Copying model artifacts"

cp models/eo_detector_fp16.engine "${RELEASE_DIR}/models/"
cp models/manifest.json "${RELEASE_DIR}/models/"

# Generate SHA256 checksums
echo "==> Generating SHA256 checksums"

(
    cd "${RELEASE_DIR}"

    find . -type f ! -name "SHA256SUMS" -print0 \
        | sort -z \
        | xargs -0 sha256sum > SHA256SUMS
)

# Verify checksums
echo "==> Verifying generated checksums"

(
    cd "${RELEASE_DIR}"
    sha256sum --check SHA256SUMS
)

# Create compressed archive
echo "==> Creating release archive"

tar -czf "${ARCHIVE}" "${RELEASE_DIR}"

# Verify archive
echo "==> Verifying archive integrity"

gzip -t "${ARCHIVE}"

# Display release information
echo ""
echo "=========================================="
echo " AIR-GAP RELEASE CREATED SUCCESSFULLY"
echo "=========================================="

echo "Version : ${VERSION}"
echo "Archive : ${ARCHIVE}"
echo "Size    : $(du -h "${ARCHIVE}" | cut -f1)"

echo ""
echo "Archive SHA256:"

sha256sum "${ARCHIVE}"

echo ""
echo "==> Packaging completed successfully"