# Basalt release archive on the CUDA 13 runtime (the archive is built with CUDA 13.0.2).
ARG CUDA_TAG=13.0.2
FROM nvidia/cuda:${CUDA_TAG}-runtime-ubuntu24.04

ARG BASALT_VERSION=0.5.6

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN curl -fsSL "https://github.com/jesdga95/basalt/releases/download/v${BASALT_VERSION}/basalt-v${BASALT_VERSION}-linux-x64.tar.gz" \
    | tar -xz \
    && mv "basalt-v${BASALT_VERSION}-linux-x64" basalt

# The archive's bin/basalt uses the venv at <archive>/.venv, so it must sit at this exact path.
RUN python3 -m venv /opt/basalt/.venv \
    && /opt/basalt/.venv/bin/pip install --no-cache-dir -r /opt/basalt/requirements.txt

ENV HOME=/data \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/basalt/bin:$PATH

EXPOSE 8080
ENTRYPOINT ["basalt", "serve", "--config", "/data/basalt_config.json", "--host", "0.0.0.0"]
