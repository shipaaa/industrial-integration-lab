FROM python:3.13.14-slim-bookworm AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/plantbridge
WORKDIR /opt/plantbridge

FROM base AS test
COPY source-simulator/requirements.txt source-simulator/requirements-test.txt ./
RUN pip install --no-cache-dir --requirement requirements-test.txt
COPY source-simulator/app ./app
COPY source-simulator/tests ./tests
COPY data/telemetry/telemetry.json ./data/telemetry.json
ENV TELEMETRY_DATA_PATH=/opt/plantbridge/data/telemetry.json
CMD ["pytest", "-q"]

FROM base AS runtime
COPY source-simulator/requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt \
    && useradd --create-home --uid 10001 plantbridge
COPY --chown=plantbridge:plantbridge source-simulator/app ./app
COPY --chown=plantbridge:plantbridge data/telemetry/telemetry.json ./data/telemetry.json
ENV TELEMETRY_DATA_PATH=/opt/plantbridge/data/telemetry.json
USER plantbridge
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
