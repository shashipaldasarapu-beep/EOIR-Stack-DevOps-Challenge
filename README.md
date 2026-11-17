# EOIR Stack – Edge Object Intelligence & Recognition

**Release Version:** 1.4.2  
**Project Type:** DevOps Engineering Challenge  
**Architecture:** Dockerized Microservices  
**Deployment:** Docker Compose and Air-Gap Deployment

---

## 1. Project Overview

EOIR Stack is a containerized vision-processing application designed to demonstrate reliable deployment, service orchestration, health monitoring, model integrity verification, and offline deployment.

The application consists of three primary services:

- Vision API
- Inference Worker
- PostgreSQL Database

The system uses Docker Compose to manage services, networks, persistent storage, and health checks.

The project also implements an air-gap deployment workflow that packages Docker images, application source files, model artifacts, and checksum manifests into a portable release archive.

## 2. Technology Stack

| Technology | Purpose |
|---|---|
| Python 3.11 | Application development |
| Docker | Containerization |
| Docker Compose | Service orchestration |
| PostgreSQL 15 | Database |
| Linux | Container runtime |
| Bash | Deployment automation |
| SHA256 | Model and release integrity |
| GitHub Actions | CI/CD automation |

## 3. System Architecture

```text
                 CLIENT
                   |
                   |
             Vision API
              Port 8000
                   |
          -------------------
          |                 |
          |                 |
    Inference Worker    PostgreSQL
       Port 9000         Port 5432
          |
          |
    Model Integrity
      Verification
          |
          |
    Simulated CPU
       Inference
```

### Services

**Vision API**
- Handles HTTP requests.
- Provides application health monitoring.
- Communicates with the inference worker.
- Exposes the detection endpoint.

**Inference Worker**
- Verifies model integrity.
- Validates SHA256 checksums.
- Provides worker health status.
- Provides simulated CPU detection responses.

**PostgreSQL**
- Provides persistent database storage.
- Uses environment-based credentials.
- Includes database readiness monitoring.

## 4. Project Structure

```text
DevOps_Challenge/
│
├── .github/
│   └── workflows/
│       └── ci.yml
│
├── vision_api/
│   └── app.py
│
├── inference_worker/
│   └── worker.py
│
├── models/
│   ├── eo_detector_fp16.engine
│   └── manifest.json
│
├── scripts/
│   ├── package_airgap.sh
│   └── deploy_airgap.sh
│
├── tests/
│   ├── test_manifest.py
│   └── verify_model.py
│
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── .env.example
├── README.md
└── RUNBOOK.md
```

## 5. Key Features

### Containerization
- Multi-stage Docker build.
- Python slim runtime image.
- Non-root execution using UID 10001.
- Application image below the 220 MB requirement.

### Health Monitoring
- Vision API health endpoint.
- Inference worker healthcheck.
- PostgreSQL readiness check.
- Docker unhealthy-state detection.

### Security
- Environment-based database credentials.
- `.env` excluded from Git.
- Dedicated non-root runtime user.
- Internal Docker network for backend services.

### Model Integrity
- SHA256 model verification.
- Manifest validation.
- Detection of corrupted model artifacts.
- Worker health failure when integrity verification fails.

### Air-Gap Deployment
- Docker image export.
- Portable release archive.
- SHA256 release manifest.
- Offline Docker image loading.
- Deployment without image building or pulling.

## 6. Installation and Setup

### Prerequisites

- Docker Desktop or Docker Engine.
- Docker Compose.
- Git.
- Bash-compatible terminal.

### Clone the repository

```bash
git clone <YOUR_GITHUB_REPOSITORY_URL>
cd DevOps_Challenge
```

Replace the placeholder with your actual repository URL.

### Configure environment variables

```bash
cp .env.example .env
```

Configure:

```env
POSTGRES_USER=c2admin
POSTGRES_PASSWORD=replace_with_a_strong_password
POSTGRES_DB=surveillance_c2
```

Never commit the actual `.env` file.

### Start the application

```bash
docker compose up -d --build
```

### Verify containers

```bash
docker compose ps
```

## 7. API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Application health |
| `/api/v1/detect` | GET | Detection endpoint |

### Health check

```bash
curl http://localhost:8000/health
```

Expected response:

```json
{
  "status": "healthy",
  "worker_ready": true
}
```

### Detection endpoint

```bash
curl http://localhost:8000/api/v1/detect
```

The current implementation returns a simulated vehicle detection response.

**Note:** The current engine is a challenge simulation fixture. Actual TensorRT deserialization, CUDA execution, and GPU inference have not been implemented.

## 8. Automated Testing

Run unit tests:

```bash
python -m unittest discover -s tests -v
```

Verify model integrity:

```bash
python tests/verify_model.py
```

Validate Python syntax:

```bash
python -m py_compile vision_api/app.py inference_worker/worker.py
```

## 9. CI/CD Pipeline

GitHub Actions workflow:

```text
.github/workflows/ci.yml
```

Pipeline stages:

1. Source checkout.
2. Python environment setup.
3. Model checksum verification.
4. Unit testing.
5. Python syntax validation.
6. Docker image build.
7. Image size verification.
8. Non-root user verification.
9. Artifact generation and checksum validation.
10. Controlled release-stage verification.

The build depends on successful tests, and the promotion job depends on the test and build jobs.

External registry publishing and production deployment still require additional configuration.

## 10. Air-Gap Deployment

Generate the release:

```bash
chmod +x scripts/package_airgap.sh
./scripts/package_airgap.sh
```

Generated archive:

```text
release_v1.4.2.tar.gz
```

Verify archive:

```bash
gzip -t release_v1.4.2.tar.gz
sha256sum release_v1.4.2.tar.gz
```

Extract:

```bash
mkdir -p ~/eoir-offline-test
tar -xzf release_v1.4.2.tar.gz -C ~/eoir-offline-test
```

Verify release files:

```bash
cd ~/eoir-offline-test/airgap_release
sha256sum --check SHA256SUMS
```

Load Docker images:

```bash
docker load -i images/docker-images.tar
```

Deploy without building or pulling:

```bash
docker compose up -d --no-build --pull never
```

Configure `.env` securely before starting services.

## 11. Failure Detection and Recovery

The inference worker performs model integrity verification.

If the engine becomes corrupted:

1. Model verification fails.
2. Worker health endpoint reports failure.
3. Docker marks the worker unhealthy.
4. The API reports the worker as unavailable.
5. The worker can be recreated from the verified image.

Example recovery:

```bash
docker compose up -d --force-recreate inference_worker
```

See `RUNBOOK.md` for detailed recovery and rollback procedures.

## 12. Platform Compatibility

The development environment uses x86_64 architecture.

Jetson Orin uses ARM64/aarch64 architecture.

Actual TensorRT engine files must be generated and validated for the target hardware and compatible CUDA/TensorRT runtime versions.

The current challenge fixture is not a production TensorRT engine.

## 13. Current Project Validation

| Requirement | Status |
|---|---|
| Docker image build | PASS |
| Multi-stage build | PASS |
| Non-root execution | PASS |
| Image size requirement | PASS |
| PostgreSQL healthcheck | PASS |
| Worker healthcheck | PASS |
| API health endpoint | PASS |
| Detection endpoint | PASS |
| Model checksum verification | PASS |
| Air-gap archive generation | PASS |
| Release checksum verification | PASS |
| Offline image loading | PASS |
| Offline deployment | PASS |
| Engine corruption detection | PASS |
| Worker recovery | PASS |
| GitHub Actions execution | Pending |
| Actual TensorRT inference | Pending |
| Jetson Orin validation | Pending |
| Timed rollback drill | Pending |

## 14. Documentation

Additional operational documentation:

- `RUNBOOK.md` – Deployment, troubleshooting, health monitoring, failure recovery, and rollback procedures.

## 15. Release Information

| Property | Value |
|---|---|
| Application | EOIR Stack |
| Release | 1.4.2 |
| Runtime | Python 3.11 |
| Container orchestration | Docker Compose |
| Database | PostgreSQL 15 |
| Deployment type | Online and Air-Gap |
| Image tag | eoir-stack:1.4.2 |

---

**Project Status:** Core containerization, offline deployment, and failure-detection tests completed. CI/CD execution and hardware-specific inference validation remain pending.