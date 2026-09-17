# syntax=docker/dockerfile:1.7
# py-base: shared FastAPI service runtime.
# Deps come from base.lock (universal, hashed) so amd64 and arm64 install the same versions.
ARG PYTHON_VERSION=3.12
ARG DEBIAN_SUITE=trixie
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_SUITE}

COPY --from=ghcr.io/astral-sh/uv:0.11.7 /uv /usr/local/bin/uv

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_PROGRESS=1

# Unprivileged runtime user; project images switch to it with `USER app`.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

# base.lock stays in the image so project builds / CI can constrain against it:
#   docker run --rm --entrypoint cat <image> /opt/py-base/base.lock
COPY base.lock /opt/py-base/base.lock

RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv pip install --require-hashes -r /opt/py-base/base.lock \
 && uv pip check \
 # aiomysql 0.3.x wheels ship top-level docs/ and examples/ into site-packages
 && SP="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \
 && rm -rf "$SP/docs" "$SP/examples" \
 && python -c "import fastapi, starlette, pydantic, uvicorn, uvloop, httptools, sqlalchemy.ext.asyncio, pymysql, aiomysql, cryptography, httpx, dotenv, python_multipart, loguru, boto3, concurrent_log_handler; from v2.nacos import NacosConfigService; print('py-base ok')"

LABEL org.opencontainers.image.title="py-base" \
      org.opencontainers.image.description="Shared FastAPI service runtime (see /opt/py-base/base.lock)"
