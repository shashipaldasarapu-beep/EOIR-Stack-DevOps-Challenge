# EOIR Stack – Operations Runbook

**Release:** v1.4.2
**Application:** Edge Object Intelligence & Recognition
**Deployment:** Docker Compose / Air-Gap
**Maintainer:** DevOps Team

## 1. System Overview

EOIR Stack contains three services:

| Service | Responsibility |
|---|---|
| `vision_api` | HTTP API exposed on port 8000 |
| `inference_worker` | Engine integrity verification and detection endpoint on port 9000 |
| `postgres` | Persistent PostgreSQL database |

The API communicates with the worker through Docker service DNS. PostgreSQL data is stored in a named Docker volume.

**Implementation limitation:** The supplied engine is a simulation fixture. Detection currently uses CPU simulation, not actual TensorRT or GPU inference. GPU compatibility guidance below describes requirements for a future production TensorRT implementation.

## 2. Original Issues and Remediation

| Original issue | Affected file | Root cause | Remediation |
|---|---|---|---|
| Oversized image | `Dockerfile` | Full Python image and unnecessary packages | Slim multi-stage build |
| Root runtime | `Dockerfile` | No dedicated runtime user | Non-root UID/GID 10001 |
| Hardcoded credentials | `docker-compose.yml` | Credentials embedded in Compose | Environment variables and ignored `.env` |
| Incorrect worker URL | `vision_api/app.py` | Used localhost instead of service DNS | `http://inference_worker:9000` |
| Premature API startup | `docker-compose.yml` | Missing readiness checks | Health checks and dependency conditions |
| False worker health | `inference_worker/worker.py` | Health check did not validate engine integrity | Manifest and SHA256 verification |
| Engine checksum mismatch | `models/manifest.json` | Manifest did not match supplied engine | Corrected SHA256 and verification test |
| Missing readiness handling | `vision_api/app.py` | API did not reliably check worker status | Worker status check and HTTP 503 on failure |
| Weak CI gates | `.github/workflows/ci.yml` | Tests could be ignored and promotion was not gated | Test → build → verify → promotion |
| Mutable image tagging | CI workflow and Compose | Release image identification was inconsistent | Versioned image tag |
| Missing offline packaging | `scripts/` | Images and deployment files were not distributed together | Air-gap archive and SHA256SUMS |

For exact historical source line numbers, consult the original source and Git diff. Do not infer line numbers from revised files.

## 3. Configuration and Startup

Create a secure environment file:

```bash
cp .env.example .env
chmod 600 .env
```

Set a strong PostgreSQL password in `.env`. Never commit `.env`.

Start the stack:

```bash
docker compose up -d --build
docker compose ps
```

Check API health:

```bash
curl -i http://localhost:8000/health
```

Expected response:

```json
{"status":"healthy","worker_ready":true}
```

Test detection:

```bash
curl -i http://localhost:8000/api/v1/detect
```

The current implementation returns simulated CPU detection results.

## 4. Health Monitoring and Failure Recovery

Check service health:

```bash
docker compose ps
docker compose logs --tail=100 inference_worker
docker compose logs --tail=100 vision_api
```

The worker health check verifies engine integrity against the model manifest. A corrupted or invalid engine should cause the worker to become unhealthy within the configured health-check period.

To test recovery in a non-production environment:

```bash
docker exec eoir-stack-inference_worker-1 sh -c 'printf "CORRUPTED_ENGINE_TEST" > /app/models/eo_detector_fp16.engine'
```

Wait for the health check to report `unhealthy`. Restore the worker from its image:

```bash
docker compose up -d --no-deps --force-recreate inference_worker
```

Verify recovery:

```bash
docker compose ps
curl http://localhost:8000/health
```

## 5. Air-Gap Release and Deployment

Build the offline release package on the connected build machine:

```bash
bash scripts/package_airgap.sh
```

Transfer `release_v1.4.2.tar.gz` to the offline target.

On the target, extract and verify the archive before loading images:

```bash
tar -xzf release_v1.4.2.tar.gz
cd airgap_release
sha256sum -c SHA256SUMS
```

Only continue if every checksum passes. Load the packaged images:

```bash
docker load -i images/docker-images.tar
```

Copy the deployment files to the deployment directory, create a secure `.env` using `.env.example`, and start the stack:

```bash
docker compose up -d --no-build --pull never
docker compose ps
```

No registry access or internet connection should be required when all required images are packaged.

## 6. Fifteen-Minute Release Rollback

**Minute 0–3: Stop promotion**
- Stop further deployment or release promotion.
- Preserve logs and identify the last known-good release archive.

**Minute 3–7: Restore previous release**
- Extract the previous verified release archive.
- Verify its `SHA256SUMS`.
- Load its Docker images using `docker load`.
- Restore its Compose configuration and deployment files.

**Minute 7–11: Restart services**

```bash
docker compose down
docker compose up -d --no-build --pull never
```

Do not delete the PostgreSQL named volume during rollback.

**Minute 11–15: Validate**
- Check `docker compose ps`.
- Check `http://localhost:8000/health`.
- Test `/api/v1/detect`.
- Review service logs.
- Confirm database persistence and notify the team.

Keep previous verified release archives available so rollback does not depend on internet access.

## 7. CUDA, TensorRT and Jetson Orin Compatibility

The current release uses CPU simulation and does not execute TensorRT inference.

For a future GPU-enabled release:

- Build separate runtime images for the intended architecture.
- Standard x86_64 NVIDIA deployments and Jetson Orin aarch64 deployments require compatible platform-specific dependencies.
- Match CUDA, TensorRT, NVIDIA driver and JetPack versions to the target platform.
- Build or validate TensorRT engines on compatible target hardware.
- Do not assume an x86_64 TensorRT engine will run on Jetson Orin.
- Validate engine loading, inference, memory usage and GPU access on the actual deployment device.

## 8. Release Checklist

- [ ] Unit tests pass.
- [ ] Model checksum verification passes.
- [ ] CI build and artifact verification pass.
- [ ] Runtime image is below 220 MB.
- [ ] Runtime uses a non-root user.
- [ ] No secrets are committed.
- [ ] API health and detection endpoints respond correctly.
- [ ] Worker corruption test detects failure.
- [ ] Air-gap archive checksums pass.
- [ ] Offline deployment and rollback procedures are documented.