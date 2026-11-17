FROM python:3.11-slim-bookworm AS builder

WORKDIR /build

COPY vision_api/ /build/vision_api/
COPY inference_worker/ /build/inference_worker/
COPY models/ /build/models/


FROM python:3.11-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app \
       --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /tmp/trt_cache \
    && chown -R app:app /app /tmp/trt_cache

COPY --from=builder --chown=app:app /build/vision_api/ /app/vision_api/
COPY --from=builder --chown=app:app /build/inference_worker/ /app/inference_worker/
COPY --from=builder --chown=app:app /build/models/ /app/models/

USER 10001:10001

EXPOSE 8000 9000

CMD ["python", "vision_api/app.py"]
