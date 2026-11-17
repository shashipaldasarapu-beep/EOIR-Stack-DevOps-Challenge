# EOIR Stack – Operations Runbook

**Release:** v1.4.2  
**Application:** Edge Object Intelligence & Recognition  
**Deployment:** Docker Compose / Air-Gap  
**Maintainer:** DevOps Team

## 1. System Overview

EOIR Stack consists of three services:

- **vision_api:** Exposes the HTTP API on port 8000.
- **inference_worker:** Verifies model integrity and provides detection responses on port 9000.
- **postgres:** Stores persistent database data.

The API and worker communicate over the internal Docker network. PostgreSQL data is stored in a persistent Docker volume.

> Current implementation note: The supplied engine is a simulation fixture. Detection responses use CPU simulation, not actual TensorRT/GPU inference.

## 2. Identified Issues and Remediation

| Original issue | Root cause | Remediation |
|---|---|---|
| Oversized Docker image | Full Python image and unnecessary OS packages | Multi-stage build using Python slim |
| Container ran as root | No non-root runtime user | Runtime user UID/GID 10001 |
| Hardcoded database credentials | Credentials embedded in Compose | Environment variables and `.env.example`; local `.env` excluded from Git |
| Incorrect worker URL | API used localhost instead of service DNS | `http://inference_worker:9000` |
| API started before dependencies were ready | Missing service readiness conditions | Compose health checks and `depends_on` conditions |
| Worker always appeared healthy | Health check did not verify engine integrity | Worker status endpoint validates manifest and SHA256 |
| Engine checksum mismatch | Manifest did not match the supplied engine file | Updated manifest checksum and verification test |
| API did not depend on worker readiness | Startup and request handling did not verify worker status | API checks worker health and returns HTTP 503 when unavailable |
| Weak CI quality gates | Tests could be ignored and promotion was not gated | Test job, dependent build job, image verification and gated promotion |
| Mutable image tagging | Release relied on a mutable tag | Versioned image tag `eoir-stack:1.4.2` |
| No reliable offline deployment | Images and deployment files were not packaged together | Air-gap packaging and SHA256 verification scripts |

File locations to inspect:
- `Dockerfile`
- `docker-compose.yml`
- `vision_api/app.py`
- `inference_worker/worker.py`
- `models/manifest.json`
- `tests/`
- `.github/workflows/ci.yml`
- `scripts/`

## 3. Configuration and Startup

Create a local environment file from the example:

```bash
cp .env.example .env
```

Edit `.env` and provide a strong database password. Never commit `.env`.

Start the services:

```bash
docker compose up -d --build
```

Check service status:

```bash
docker compose ps
```

Check logs:

```bash
docker compose logs -f
```

## 4. Health and API Verification

Check API health:

```bash
curl -i http://localhost:8000/health
```

Expected healthy response:

```json
{"status":"healthy","worker_ready":true}
```

Check detection:

```bash
curl -i http://localhost:8000/api/v1/detect
```

The current implementation returns a simulated detection response.

Check worker health:

```bash
docker inspect eoir-stack-inference_worker-1 \
  --format '{{.State.Health.Status}}'
```

Expected status:

```text
healthy
```

## 5. Engine Corruption and Recovery

The worker verifies the engine checksum against `models/manifest.json`.

To simulate engine corruption in a test environment:

```bash
docker exec eoir-stack-inference_worker-1 sh -c \
  'printf CORRUPTED_ENGINE_TEST > /app/models/eo_detector_fp16.engine'
```

Wait for the health check:

```bash
sleep 12
docker inspect eoir-stack-inference_worker-1 \
  --format '{{.State.Health.Status}}'
```

Expected result:

```text
unhealthy
```

Restore the worker from the image:

```bash
docker compose up -d --force-recreate inference_worker
```

Verify recovery:

```bash
docker compose ps
curl -i http://localhost:8000/health
```

**Warning:** Perform corruption testing only in a test deployment, never on a production worker.

## 6. Air-Gap Packaging and Deployment

On the connected build machine:

```bash
bash scripts/package_airgap.sh
```

The script creates:

```text
release_v1.4.2.tar.gz
```

Transfer the archive to the offline target.

Extract it:

```bash
tar -xzf release_v1.4.2.tar.gz
```

Verify package integrity:

```bash
cd airgap_release
sha256sum --check SHA256SUMS
```

Only continue if every checksum passes.

Load the packaged images:

```bash
docker load -i images/docker-images.tar
```

Prepare deployment configuration:

```bash
mkdir -p /opt/eoir-stack
cp deployment/docker-compose.yml /opt/eoir-stack/
cp deployment/.env.example /opt/eoir-stack/.env
```

Edit `/opt/eoir-stack/.env` with secure deployment credentials.

Start without building or pulling images:

```bash
cd /opt/eoir-stack
docker compose up -d --no-build --pull never
```

Verify:

```bash
docker compose ps
```

## 7. Fifteen-Minute Release Rollback Procedure

**Scenario:** A newly promoted engine or application release fails after deployment.

**Minute 0–3: Detect and assess**
- Check API health and worker health.
- Inspect worker and API logs.
- Confirm whether the failure is related to engine integrity, application startup or architecture compatibility.

```bash
docker compose ps
docker compose logs --tail=100 inference_worker vision_api
```

**Minute 3–5: Stop further promotion**
- Pause additional deployment activity.
- Preserve