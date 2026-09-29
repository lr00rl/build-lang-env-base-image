# syntax=docker/dockerfile:1.7
#
# node-base: official Node on Debian slim (default) or Alpine, plus the shared
# `app` user (uid 10001).
#
# Why trixie-slim is the default, not alpine:
#   Service Dockerfiles need `apt-get install` (fonts, chromium, a CLI) the
#   same way they do on python-base, rust-runtime, and java-base, which are all
#   Debian or Ubuntu. Alpine only has apk. trixie matches python-base and the
#   rust pair (Debian 13, glibc 2.41), and glibc takes the prebuilt linux-gnu
#   binaries of native addons (sharp, @next/swc, rollup) instead of the musl
#   ones. Official node:<N>-trixie-slim publishes linux/amd64 and linux/arm64
#   for 20 and 22.
#
# Alpine is still buildable with DISTRO=alpine (and is the only choice for 18:
#   there is no node:18-trixie-slim). On Harbor this Debian build is pushed
#   over node:20-alpine-multiarch and node:22-alpine-multiarch, which the
#   frontends already FROM; the Alpine builds are kept as *-alpine-multiarch-musl.
#   Those names now lie, so a child that runs `apk add` against them breaks.
#
# Lines we build:
#   make node-build-versions                    # 20-trixie, 22-trixie
#   make node-build-versions DISTRO=alpine NODES="18 20 22"
#   or one line: make node-build-local-multi NODE=22
#
# This image is the parent, not the app:
#   no package.json, no pnpm/yarn pin, no NODE_ENV=production. Services
#   pin pnpm themselves (10.x vs 11.x) and set NODE_ENV in the child
#   Dockerfile. Official node already ships npm and corepack.
#
# Do not install a compiler here. python3 / make / g++ belong in a
# service *builder* stage that compiles native addons, then copy the
# result into this runtime.
ARG NODE_VERSION=20
ARG DISTRO=trixie-slim
FROM node:${NODE_VERSION}-${DISTRO}
# Re-declared so the LABEL below can name the distro.
ARG DISTRO

# NODE_ENV stays unset. Baking production here would skip devDependencies
# for any child that `npm ci`s without flipping it back.
ENV LANG=C.UTF-8

# Debian: official node slim purges ca-certificates after it installs node,
# so /etc/ssl/certs does not exist. Node itself carries a CA bundle, but curl,
# git, and anything using --use-openssl-ca read the OS store, which Alpine had
# (ca-certificates-bundle). Put it back so moving off Alpine changes nothing
# there. tzdata is already in the Debian slim image.
#
# Same uid as python-base / java-base / rust-runtime. Official node already has
# user `node` (uid 1000); we do not reuse it. Default stays root so a child
# Dockerfile can apt-get / chmod / mkdir without an extra USER dance.
# Debian has useradd; Alpine only has busybox adduser, with different flags.
# uid 10001 is above SYS_UID_MAX (999), so useradd --system warns. Ignore that.
RUN set -eu; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      apt-get install -y --no-install-recommends ca-certificates; \
      rm -rf /var/lib/apt/lists/*; \
      groupadd --system --gid 10001 app; \
      useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app; \
    else \
      addgroup -g 10001 -S app; \
      adduser -u 10001 -S -G app -h /app -s /sbin/nologin app; \
    fi; \
    mkdir -p /app/logs; \
    chown app:app /app /app/logs

WORKDIR /app

LABEL org.opencontainers.image.title="node-base" \
      org.opencontainers.image.description="Official Node (${DISTRO}) plus uid 10001 (linux/amd64 + linux/arm64)"

# Smoke / default. Service images override with CMD node server.mjs (or pnpm start).
CMD ["node", "--version"]
