# node-base

Official Node on Debian 13 slim (`trixie-slim`), plus `ca-certificates` and the shared `app` user (uid 10001). Alpine is still buildable with `DISTRO=alpine`.

| Local tag | Parent | Who uses that Node line |
| --- | --- | --- |
| `node-base:20-trixie` | `node:20-trixie-slim` | Argus web stage, platform-ui-oauth |
| `node-base:22-trixie` | `node:22-trixie-slim` | platform-ui (and its casebook stage) |
| `node-base:18-alpine` / `20-alpine` / `22-alpine` | `node:<N>-alpine` | the older musl lines, `DISTRO=alpine` |

Each line also has `-arm64` and `-amd64` single-arch tags. Official `node:20-trixie-slim` and `node:22-trixie-slim` publish `linux/amd64` and `linux/arm64`. There is no `node:18-trixie-slim`; Node 18 only builds with `DISTRO=alpine`.

Node 20 reached end of life on 2026-04-30, and Docker Hub last rebuilt `node:20-trixie-slim` on 2026-04-22, so it gets no more security fixes. The 20 line stays only for the services still on it; move them to 22.

## Why trixie-slim, not alpine

Service Dockerfiles need `apt-get install` on every language base the same way. python-base and the rust pair are Debian trixie and java-base is Ubuntu jammy; Alpine only has `apk`, so a frontend that needed fonts, chromium, or a CLI had to learn a second package manager and a second set of package names. trixie also matches python-base and rust-runtime exactly (Debian 13, glibc 2.41).

On glibc, pnpm and npm install the `linux-*-gnu` builds of native addons (`@img/sharp-linux-*`, `@next/swc-linux-*-gnu`, `@rollup/rollup-linux-*-gnu`) instead of the musl ones. The lockfiles of the Falcon frontends already list both, so `pnpm install --frozen-lockfile` and `npm ci` work without regenerating the lock.

Official Node slim purges `ca-certificates` after installing Node, which leaves no `/etc/ssl/certs`. Node carries its own CA bundle, but curl, git, and `--use-openssl-ca` read the OS store, which the Alpine image had. This image installs `ca-certificates` again so switching from Alpine does not remove it.

The cost is size. On arm64, `node-base:20-trixie` is 334 MB unpacked against 194 MB for `node-base:20-alpine`; `ca-certificates` is 15 MB of the difference, Debian's libc and base tools the rest.

Do not `apt-get install g++ python3` in this image: a compiler belongs in the service builder stage.

## Harbor tags

The frontends `FROM` `node:20-alpine-multiarch` and `node:22-alpine-multiarch`, so the Debian builds went over those two names on 2026-09-28 and the services switch without a Dockerfile change:

| Harbor tag | Now | Previous Alpine build, kept as |
| --- | --- | --- |
| `node:20-alpine-multiarch` | `sha256:a83a02d1b1bc27a301ce5ee360381302f962a607537f5df7f62d085a2edb5864` (Node 20.20.2, trixie) | `node:20-alpine-multiarch-musl` (`sha256:ef18b705d923…`) |
| `node:22-alpine-multiarch` | `sha256:047b1e48d61585faf9217b140660f48a9ef5bc0782fecffd2ce5dfeeaeef8b41` (Node 22.23.3, trixie) | `node:22-alpine-multiarch-musl` (`sha256:52ff91791f93…`) |

The names then no longer describe the contents. A child that runs `apk add` against them fails on its next build; that is how `job-recruiter` broke after `openjdk:17-alpine` was overwritten with Ubuntu. The `org.opencontainers.image.version` label on the image still says `20-trixie-multiarch` / `22-trixie-multiarch`.

To refresh one of them later, keep the current build under its own tag first, so rollback is one command:

```bash
H=harbor.openjobs-ai.com/openjobs-ai/node
crane tag $H:20-alpine-multiarch 20-alpine-multiarch-prev
make node-builder
make node-push REGISTRY=harbor.openjobs-ai.com/openjobs-ai NAME=node NODE=20 VERSION=multiarch ALIAS_TAG=20-alpine-multiarch
# rollback: crane tag $H:20-alpine-multiarch-prev 20-alpine-multiarch
```

That also writes `node:20-trixie-multiarch`, a name that matches the contents, for services that want to move off the `-alpine` name.

## What this image is not

It is not the application. There is no `COPY package.json`, no pinned pnpm, no `NODE_ENV=production`. Services pin pnpm themselves (10.x vs 11.x) and set `NODE_ENV` in the child Dockerfile. Official Node already ships `npm` and `corepack`.

Default `CMD` is `node --version` so `make node-smoke` has something to run. The child image overrides it.

## Build

From the repo root, both Debian lines (each arm64, amd64, and a dual-arch index):

```bash
make node-build-versions
make node-smoke-versions
```

One version:

```bash
make node-build-local-arm64 NODE=22   # node-base:22-trixie-arm64
make node-build-local-amd64 NODE=22   # node-base:22-trixie-amd64
make node-build-local-multi NODE=22   # node-base:22-trixie and :22-trixie-multi
make node-smoke-arm64 node-smoke-amd64 node-smoke-multi NODE=22
make node-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1 NODE=20
```

The Alpine lines: `make node-build-versions DISTRO=alpine NODES="18 20 22"`. If `node-gyp` fails because amd64 and arm64 Alpine patch versions drifted under the floating `20-alpine` tag, pin `DISTRO=alpine3.22` (or whichever patch Hub currently publishes for both platforms). The tag line drops `-slim` (`DISTRO=trixie-slim` gives `20-trixie`, like `rust-runtime:trixie`).

Harbor (`openjobs-ai/node`), dual-arch only:

```bash
docker login harbor.openjobs-ai.com
make node-builder
make node-push-versions \
  REGISTRY=harbor.openjobs-ai.com/openjobs-ai \
  NAME=node \
  VERSION=multiarch
```

That pushes `node:20-trixie-multiarch` and `node:22-trixie-multiarch`. It does not touch the `*-alpine` or `*-alpine-multiarch` tags. One version: `make node-push REGISTRY=... NAME=node NODE=22 VERSION=multiarch ALIAS_TAG=`.

From this directory: `make build-versions && make smoke-versions`.

`--load` needs a docker-driver builder (Colima: `colima`, Docker Desktop: `desktop-linux`). Multi-arch `--push` uses the `multiarch` docker-container builder (`make node-builder` creates it).

Push tags `$REGISTRY/node-base:20-trixie-2026.09.1` and `$REGISTRY/node-base:20-trixie` (change `NODE` for 22). To reuse an existing registry repo named `node`, pass `NAME=node`. Do not `docker tag` a native arm64 image and push it: amd64 nodes then fail with `exec format error`.

## Use it from a service

Builder-only frontend (static files copied into nginx or a Python runtime):

```dockerfile
# syntax=docker/dockerfile:1.7
ARG NODE_IMAGE=node-base:20-trixie
FROM ${NODE_IMAGE} AS web
WORKDIR /web
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build
```

Next.js-style runtime on the same parent, with an OS package:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=node-base:20-trixie
FROM ${BASE_IMAGE}
WORKDIR /app
# apt-get runs as root, so it goes before USER app.
RUN apt-get update \
 && apt-get install -y --no-install-recommends fonts-noto-cjk \
 && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production
COPY --chown=app:app .next .next
COPY --chown=app:app node_modules node_modules
COPY --chown=app:app package.json server.mjs ./
USER app
EXPOSE 3000
CMD ["node", "server.mjs"]
```

`ARG BASE_IMAGE` / `ARG NODE_IMAGE` must sit above `FROM`. Keep secrets out of the image. `npm ci` of native addons that need a compiler belongs in a builder stage, not in this runtime.
