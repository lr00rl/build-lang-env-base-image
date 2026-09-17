# syntax=docker/dockerfile:1.7
#
# java-base: Eclipse Temurin 17 JDK on Ubuntu 22.04 (jammy).
#
# Why jammy, not alpine:
#   eclipse-temurin:17-jdk-alpine is linux/amd64 only. A Jenkins job that
#   publishes linux/amd64,linux/arm64 (or a Mac arm64 laptop that --load's
#   the image) cannot use that tag. jammy publishes both architectures.
#
# Why JDK, not JRE:
#   Service Dockerfiles today run `java -jar`. They also want jcmd / jmap
#   in an incident. The JRE image drops those tools. If you only ever run
#   the jar and never debug in-cluster, you can switch DISTRO's sibling
#   tag to 17-jre-jammy by changing the FROM line.
#
# This image is the parent, not the app:
#   no jar, no Spring profile, no heap size. Those belong in the service
#   Dockerfile (COPY the jar, set JAVA_OPTS / SPRING_PROFILES_ACTIVE).
#
# Alpine leftovers you should not copy here:
#   `apk add libstdc++ gcompat` was for musl + JNI. jammy is glibc;
#   libstdc++6 is already in the Temurin image. gcompat does not exist
#   as an apt package and is not needed.
ARG JAVA_VERSION=17
ARG DISTRO=jammy
FROM eclipse-temurin:${JAVA_VERSION}-jdk-${DISTRO}

# Temurin already sets JAVA_HOME and puts java on PATH.
# JAVA_OPTS / SPRING_PROFILES_ACTIVE stay empty so a service can export them
# at runtime without fighting a baked-in -Xmx.
ENV LANG=C.UTF-8 \
    JAVA_OPTS="" \
    JAVA_TOOL_OPTIONS=""

# Same uid as python-base. Service images that want it write `USER app`
# after root-only steps. Default stays root so `chmod` / `mkdir` in a child
# Dockerfile do not need an extra USER dance.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
 && mkdir -p /app/logs \
 && chown app:app /app /app/logs

WORKDIR /app

LABEL org.opencontainers.image.title="java-base" \
      org.opencontainers.image.description="Eclipse Temurin 17 JDK on Ubuntu jammy (linux/amd64 + linux/arm64)"

# Smoke / default. Service images override with CMD java $JAVA_OPTS -jar app.jar
CMD ["java", "-version"]
