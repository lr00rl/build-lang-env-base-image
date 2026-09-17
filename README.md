# py-base

A shared Docker runtime for FastAPI services: CPython 3.12 on Debian slim (trixie), plus a hashed lock of the common stack (FastAPI, Starlette, SQLAlchemy asyncio, aiomysql, httpx, uvicorn, and a few others). Service images `FROM` this and install only what they still need. The same nodes then share one copy of the FastAPI layer instead of reinstalling it on every build.

This is not Astral's `uv python`. The interpreter is official `python:3.12-slim-trixie`. `uv` is copied in as an installer (`UV_SYSTEM_PYTHON=1`) and used for `uv pip compile` / `uv pip install --require-hashes`.

## Layout

| File | Role |
| --- | --- |
| `base.in` | Top-level packages you edit |
| `base.lock` | `uv pip compile` output: every transitive, every wheel hash, amd64 and arm64 |
| `Dockerfile` | Installs the lock into the slim image, leaves a copy at `/opt/py-base/base.lock` |
| `Makefile` | lock, audit, local build, smoke, multi-arch push |
| `req_analyze.py` | Optional helper: scan several `requirements*` files for packages shared by N projects |

`.dockerignore` is `*` then `!base.lock`. The image build never sees `base.in`. Change `.in`, run `make lock`, then rebuild.

## What the image contains

Pinned or ranged in `base.in`, resolved in `base.lock` (rebuild the image after you change the lock):

| Package | `base.in` | Locked (this tree) |
| --- | --- | --- |
| fastapi | `==0.133.1` | 0.133.1 |
| starlette | `>=1.3.1` | 1.6.0 |
| pydantic | `==2.12.5` | 2.12.5 |
| uvicorn | `uvicorn[standard]` | 0.53.0 |
| sqlalchemy | `sqlalchemy[asyncio]>=2.0.47,<2.1` | 2.0.54 |
| pymysql | unpinned | 1.2.0 |
| aiomysql | `>=0.3.0` | 0.3.2 |
| cryptography | `>=50` | 50.0.1 |
| httpx | `>=0.28.1,<1` | 0.28.1 |
| python-dotenv | `>=1.2.2` | 1.2.3 |
| python-multipart | `>=0.0.31` | 0.0.32 |
| loguru | unpinned | 0.7.3 |
| nacos-sdk-python | `>=2.0.8,<3` | 2.0.11 |
| boto3 | unpinned | 1.43.96 |
| concurrent-log-handler | unpinned | 0.9.29 |

`uvicorn[standard]` also pulls httptools, uvloop, watchfiles, websockets, and PyYAML. `sqlalchemy[asyncio]` pulls greenlet. `nacos-sdk-python` pulls grpcio, protobuf, aiohttp, and a set of `alibabacloud-*` packages. The lock is universal, so Windows-only rows (`colorama`, `win32-setctime`) stay in the file and are skipped on Linux.

The image also has:

- `/usr/local/bin/uv` from `ghcr.io/astral-sh/uv:0.11.7`
- a system user `app` (uid/gid 10001). Default user is still root; service Dockerfiles that want the unprivileged user write `USER app`
- `/opt/py-base/base.lock` for service builds and CI to constrain against

Debian slim has no compiler. Only wheels, or pure-Python sdists, will install.

## Build locally

Needs Docker Buildx and a **docker-driver** builder (`docker buildx ls`). Colima names that builder `colima`; Docker Desktop names it `desktop-linux`. The Makefile picks the first docker-driver builder it sees. The `multiarch` builder (docker-container driver) is for `--push` only; it cannot `--load` a local tag.

```bash
make lock            # base.in -> base.lock
make audit           # uvx pip-audit on the lock
make build-local     # py-base:local, native arch
make smoke
```

Force a rebuild without BuildKit cache:

```bash
docker buildx ls
docker buildx build --builder <that-docker-driver-name> --load --no-cache -t py-base:local .
```

`make build-local-amd64` emulates amd64 on Apple Silicon. Do not `docker tag` a native arm64 image and push it as a multi-arch tag: amd64 nodes then fail with `exec format error`.

## Use it from a service

Edit a `requirements.in` of top-level imports only. Packages already in this image should be unpinned so `-c` aligns them. Pin only what the service owns.

```bash
# lock next to this repo
uv pip compile requirements.in -c ../py-base/base.lock \
  --universal --python-version 3.12 --generate-hashes -o requirements.lock

# or pull the lock out of an already-built image
docker run --rm --entrypoint cat py-base:local /opt/py-base/base.lock > .py-base.lock
uv pip compile requirements.in -c .py-base.lock \
  --universal --python-version 3.12 --generate-hashes -o requirements.lock
```

Service Dockerfile (replace the `FROM` line with your registry tag after you push):

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=py-base:local
FROM ${BASE_IMAGE}

WORKDIR /app
COPY requirements.lock /tmp/requirements.lock
RUN --mount=type=cache,target=/root/.cache/uv \
    python -c "import importlib.metadata as m, json; open('/tmp/base-pkgs.json','w').write(json.dumps({(d.metadata['Name'] or '').lower(): d.version for d in m.distributions()}))" \
 && uv pip install --require-hashes -c /opt/py-base/base.lock -r /tmp/requirements.lock \
 && python -c "import importlib.metadata as m, json, sys; before=json.load(open('/tmp/base-pkgs.json')); after={(d.metadata['Name'] or '').lower(): d.version for d in m.distributions()}; changed={k: (before[k], after.get(k)) for k in before if after.get(k) != before[k]}; print('base packages changed:', changed) if changed else print('base packages unchanged:', len(before)); sys.exit(1 if changed else 0)"

COPY . .
```

`ARG BASE_IMAGE` must sit above `FROM`, or Docker cannot use it in `FROM`. The snapshot check fails the build if the service lock moves any package that was already in the base image.

Do not `uv pip install --exact -r requirements.lock` on top of this image. A service lock lists only that service's closure; `--exact` uninstalls everything else (nacos, and the rest of the base set). Default `uv pip install -r` only adds.

Keep `.env` out of the image (`.dockerignore`). Pass config at run time (`--env-file`, Kubernetes secrets). `COPY . .` of a git-tracked dotenv file puts credentials in every layer.

## Change a dependency

Service-only package: edit that service's `requirements.in`, recompile against `base.lock`, rebuild the service image.

Shared stack (fastapi, sqlalchemy, starlette, …): edit `base.in` here, `make lock`, rebuild and push a new py-base tag, then recompile every service lock against the new `base.lock`. `make upgrade` re-resolves to the newest versions `base.in` still allows.

## Push a multi-arch image

```bash
make push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

That builds `linux/amd64` and `linux/arm64`, tags `$REGISTRY/py-base:3.12-trixie-2026.09.1` and `$REGISTRY/py-base:3.12-trixie`, and prints `tag@sha256:…` (needs [crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) on `PATH`). `REGISTRY` has no default so a clone cannot push to someone else's registry by accident.

If you only need one architecture, call `docker buildx build` yourself with a single `--platform`. Keep `--push` on a docker-container builder (`make builder` creates `multiarch`).

## Scan several projects for shared packages

```bash
uv run req_analyze.py scan path/to/a/requirements.in path/to/b/requirements.txt \
  --min 2 --pypi --py 312
```

Freeze files mix transitives (`h11`, `idna`) with top-level imports. A `CONFLICT` on those rows is often noise. Align the real direct dependencies.

## License

Add a license file before you publish the GitHub repo. This tree does not ship one yet.
