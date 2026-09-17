# node-base

Official Node on Alpine, plus the shared `app` user (uid 10001). Three lines, matching Harbor and the frontends that already `FROM` those tags:

| Local tag | Parent | Who uses that Node line |
| --- | --- | --- |
| `node-base:18-alpine` | `node:18-alpine` | Harbor still has `18-alpine` |
| `node-base:20-alpine` | `node:20-alpine` | Argus / platform-ui default |
| `node-base:22-alpine` | `node:22-alpine` | recruiter-ui, metix-homepage |

Each line also has `-arm64` and `-amd64` single-arch tags. Official `node:<N>-alpine` publishes `linux/amd64` and `linux/arm64`.

## Why alpine, not bookworm

Harbor already mirrors `20-alpine` and `18-alpine`. Unlike Temurin 17 Alpine (amd64-only), official Node Alpine is dual-arch, so a Jenkins `--platform linux/amd64,linux/arm64` publish and an arm64 laptop `--load` both work.

Alpine is musl. A native addon that only ships glibc binaries needs `DISTRO=bookworm-slim` instead (or a musl build of that addon). Do not `apk add g++ python3` in this image: a compiler belongs in the service builder stage.

## What this image is not

It is not the application. There is no `COPY package.json`, no pinned pnpm, no `NODE_ENV=production`. Services pin pnpm themselves (10.x vs 11.x) and set `NODE_ENV` in the child Dockerfile. Official Node already ships `npm` and `corepack`.

Default `CMD` is `node --version` so `make node-smoke` has something to run. The child image overrides it.

## Build

From the repo root, all three versions (each arm64, amd64, and a dual-arch index):

```bash
make node-build-versions
make node-smoke-versions
```

One version:

```bash
make node-build-local-arm64 NODE=22   # node-base:22-alpine-arm64
make node-build-local-amd64 NODE=22   # node-base:22-alpine-amd64
make node-build-local-multi NODE=22   # node-base:22-alpine and :22-alpine-multi
make node-smoke-arm64 node-smoke-amd64 node-smoke-multi NODE=22
make node-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1 NODE=20
```

Harbor (`openjobs-ai/node`), dual-arch only, tags like `17-jammy-multiarch` on Java:

```bash
docker login harbor.openjobs-ai.com
make node-builder
make node-push-versions \
  REGISTRY=harbor.openjobs-ai.com/openjobs-ai \
  NAME=node \
  VERSION=multiarch
```

That pushes `node:18-alpine-multiarch`, `node:20-alpine-multiarch`, and `node:22-alpine-multiarch`. It does not move the existing `18-alpine` / `20-alpine` mirrors. One version: `make node-push REGISTRY=... NAME=node NODE=18 VERSION=multiarch ALIAS_TAG=`.

`DISTRO=bookworm-slim` is the glibc escape hatch if a native addon has no musl build. Confirm that Hub tag exists for both platforms first.

From this directory: `make build-versions && make smoke-versions`.

`--load` needs a docker-driver builder (Colima: `colima`, Docker Desktop: `desktop-linux`). Multi-arch `--push` uses the `multiarch` docker-container builder (`make node-builder` creates it).

Push tags `$REGISTRY/node-base:20-alpine-2026.09.1` and `$REGISTRY/node-base:20-alpine` (change `NODE` for 18 or 22). To reuse an existing registry repo named `node`, pass `NAME=node`. Do not `docker tag` a native arm64 image and push it: amd64 nodes then fail with `exec format error`.

## Use it from a service

Builder-only frontend (static files copied into nginx or a Python runtime):

```dockerfile
# syntax=docker/dockerfile:1.7
ARG NODE_IMAGE=node-base:20-alpine
FROM ${NODE_IMAGE} AS web
WORKDIR /web
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build
```

Next.js-style runtime on the same parent:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=node-base:20-alpine
FROM ${BASE_IMAGE}
WORKDIR /app
ENV NODE_ENV=production
COPY --chown=app:app .next .next
COPY --chown=app:app node_modules node_modules
COPY --chown=app:app package.json server.mjs ./
USER app
EXPOSE 3000
CMD ["node", "server.mjs"]
```

`ARG BASE_IMAGE` / `ARG NODE_IMAGE` must sit above `FROM`. Keep secrets out of the image. `npm ci` of native addons that need a compiler belongs in a builder stage, not in this runtime.

If `node-gyp` fails because amd64 and arm64 Alpine patch versions drifted under the floating `20-alpine` tag, pin `DISTRO=alpine3.22` (or whichever patch Hub currently publishes for both platforms).
