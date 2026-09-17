# java-base

Eclipse Temurin 17 JDK on Ubuntu 22.04 (jammy), built for `linux/amd64` and `linux/arm64`. Service images `FROM` this, copy a jar, and set `JAVA_OPTS`.

## Why jammy, not alpine

`eclipse-temurin:17-jdk-alpine` is **linux/amd64 only**. A dual-arch Jenkins publish (`--platform linux/amd64,linux/arm64`) cannot use it, and neither can an arm64 laptop that `--load`s the image. jammy publishes both.

Alpine also needed `apk add libstdc++ gcompat` for JNI on musl. jammy is glibc; Temurin already ships `libstdc++6`. Do not copy that `apk` line into this Dockerfile.

## What this image is not

It is not the application. There is no `COPY *.jar`, no `SPRING_PROFILES_ACTIVE`, no `-Xmx`. Heap and profile differ per service (one uses `MaxRAMPercentage=75`, another hard-codes `-Xmx2g`). Those stay in the child Dockerfile so a base rebuild does not rewrite everyone's memory cap.

Default `CMD` is `java -version` so `make java-smoke` has something to run. The child image overrides it.

## Build

From the repo root:

```bash
make java-build-local
make java-smoke
make java-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

Three local tags (arm-only, amd-only, dual-arch index):

```bash
make java-build-local-arm64   # java-base:local-arm64
make java-build-local-amd64   # java-base:local-amd64
make java-build-local-multi   # java-base:local-multi  (linux/amd64 + linux/arm64)
make java-smoke-arm64 java-smoke-amd64 java-smoke-multi
```

From this directory: `make build-local && make smoke`.

`--load` needs a docker-driver builder (Colima: `colima`, Docker Desktop: `desktop-linux`). Multi-arch `--push` uses the `multiarch` docker-container builder (`make java-builder` creates it).

Push tags `$REGISTRY/java-base:17-jdk-jammy-2026.09.1` and `$REGISTRY/java-base:17-jdk-jammy`. Do not `docker tag` a native arm64 image and push it: amd64 nodes then fail with `exec format error`.

`JAVA` and `DISTRO` are Makefile / build-args if you need 21 later: `make java-build-local JAVA=21`. Confirm that Temurin tag exists for both platforms first.

## Use it from a service

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=java-base:local
FROM ${BASE_IMAGE}

WORKDIR /app
COPY target/app.jar app.jar

ENV SPRING_PROFILES_ACTIVE=dev \
    JAVA_OPTS="\
-XX:+UseG1GC \
-XX:MaxRAMPercentage=75 \
-XX:+ExitOnOutOfMemoryError \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/app/logs"

EXPOSE 8080
# exec so PID 1 is the JVM and signals reach it.
CMD ["sh", "-c", "exec java $JAVA_OPTS -Dspring.profiles.active=${SPRING_PROFILES_ACTIVE} -jar app.jar"]
```

`ARG BASE_IMAGE` must sit above `FROM`. Logs go under `/app/logs`, which the base image creates and chowns to `app`. To run as uid 10001, add `USER app` after the `COPY` (the jar must be readable by that user: `COPY --chown=app:app`).

Keep secrets out of the image. Spring config belongs in the environment, a mounted file, or your config centre, not a `COPY .env`.
