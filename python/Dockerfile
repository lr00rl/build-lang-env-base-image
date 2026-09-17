# syntax=docker/dockerfile:1.7
#
# python-base: CPython 3.12 on Debian slim, plus a hashed FastAPI/SQLAlchemy stack.
#
# Why a lock, not `pip install fastapi sqlalchemy ...` in the Dockerfile:
#   uv pip compile --universal writes one hash per wheel for amd64 and arm64.
#   Both architectures then install the same package versions. A floating
#   `pip install` on two platforms can resolve two different sets.
#
# Why slim-trixie, not alpine:
#   Most of this stack ships manylinux wheels. Alpine is musl; those wheels
#   do not apply, and the image has no compiler, so installs fall over.
#
# This is not Astral's `uv python`. The interpreter is Docker Hub
# python:3.12-slim-trixie. uv is copied in as an installer only
# (UV_SYSTEM_PYTHON=1).
ARG PYTHON_VERSION=3.12
ARG DEBIAN_SUITE=trixie
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_SUITE}

# Pin the uv *installer* by tag. Bump this when you want a newer uv, then rebuild.
COPY --from=ghcr.io/astral-sh/uv:0.11.7 /uv /usr/local/bin/uv

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_PROGRESS=1

# uid 10001 is above SYS_UID_MAX (999), so useradd --system warns. Ignore that.
# Service images that want the unprivileged user write `USER app` after they
# finish root-only steps (chmod, mkdir). Default remains root, same as official slim.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

# The lock lives in the image so a service build / CI job can constrain against
# it without checking this git repo out:
#   docker run --rm --entrypoint cat <image> /opt/python-base/base.lock
COPY base.lock /opt/python-base/base.lock

RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    uv pip install --require-hashes -r /opt/python-base/base.lock \
 && uv pip check \
 # aiomysql 0.3.x wheels drop top-level docs/ and examples/ into site-packages
 && SP="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \
 && rm -rf "$SP/docs" "$SP/examples" \
 && python -c "import fastapi, starlette, pydantic, uvicorn, uvloop, httptools, sqlalchemy.ext.asyncio, pymysql, aiomysql, cryptography, httpx, dotenv, python_multipart, loguru, boto3, concurrent_log_handler; from v2.nacos import NacosConfigService; print('python-base ok')"

LABEL org.opencontainers.image.title="python-base" \
      org.opencontainers.image.description="CPython 3.12 slim + hashed FastAPI stack (see /opt/python-base/base.lock)"
