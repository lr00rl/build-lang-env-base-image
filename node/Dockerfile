# syntax=docker/dockerfile:1.7
#
# node-base: official Node on Alpine, plus the shared `app` user (uid 10001).
#
# Why alpine, not bookworm-slim:
#   Harbor already mirrors node:20-alpine and node:18-alpine. Official
#   node:<N>-alpine publishes linux/amd64 and linux/arm64 (unlike Temurin
#   17 Alpine, which is amd64-only). Services that already FROM that tag
#   keep the same musl ABI. If a native addon needs glibc (sharp without
#   a musl build, some oracle clients), rebuild with DISTRO=bookworm-slim.
#
# Three alpine lines we actually build:
#   18 (Harbor still serves 18-alpine)
#   20 (Harbor default for Argus / platform-ui)
#   22 (recruiter-ui, metix-homepage)
#   make node-build-versions
#   or: make node-build-local-multi NODE=22
#
# This image is the parent, not the app:
#   no package.json, no pnpm/yarn pin, no NODE_ENV=production. Services
#   pin pnpm themselves (10.x vs 11.x) and set NODE_ENV in the child
#   Dockerfile. Official node already ships npm and corepack.
#
# Do not apk-add a compiler here. python3 / make / g++ belong in a
# service *builder* stage that compiles native addons, then copy the
# result into this runtime.
ARG NODE_VERSION=20
ARG DISTRO=alpine
FROM node:${NODE_VERSION}-${DISTRO}

# NODE_ENV stays unset. Baking production here would skip devDependencies
# for any child that `npm ci`s without flipping it back.
ENV LANG=C.UTF-8

# Same uid as python-base / java-base. Official node already has user
# `node` (uid 1000); we do not reuse it. Default stays root so a child
# Dockerfile can chmod / mkdir without an extra USER dance.
# Alpine has adduser, not useradd.
RUN addgroup -g 10001 -S app \
 && adduser -u 10001 -S -G app -h /app -s /sbin/nologin app \
 && mkdir -p /app/logs \
 && chown app:app /app /app/logs

WORKDIR /app

LABEL org.opencontainers.image.title="node-base" \
      org.opencontainers.image.description="Official Node on Alpine plus uid 10001 (linux/amd64 + linux/arm64)"

# Smoke / default. Service images override with CMD node server.mjs (or pnpm start).
CMD ["node", "--version"]
