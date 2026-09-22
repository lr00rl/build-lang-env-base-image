# syntax=docker/dockerfile:1.7
#
# Two images out of one file:
#   --target toolchain -> rust-base     rustc, cargo, clippy, rustfmt, a C
#                                       toolchain for both GNU linux triples,
#                                       and a cargo-fetched data-query crate graph
#   --target runtime   -> rust-runtime  Debian slim + ca-certificates, no Rust
#
# Why two, when python-base is one:
#   A Python service runs on its interpreter, so the base image is also the
#   runtime. A Rust service ships one compiled binary. Leaving cargo and ~1.5 GB
#   of toolchain in the deployed image would be two orders of magnitude of
#   payload for nothing. The service Dockerfile compiles in the first image and
#   copies the binary into the second.
#
# Why they share a file:
#   The pair has to agree on libc. A binary linked against trixie's glibc 2.41
#   does not start on a bookworm runtime ("GLIBC_2.41 not found"). One
#   DEBIAN_SUITE arg drives both, so the two cannot drift apart.
#
# Why Debian, not Alpine:
#   -sys crates that compile C (zstd-sys, ring, aws-lc-sys) need a full musl
#   toolchain on Alpine, and musl's allocator is markedly slower on
#   allocation-heavy work such as DataFusion query execution. A service that
#   really wants a static binary can add the target in its own builder stage:
#   `rustup target add x86_64-unknown-linux-musl`.
#
# Why not scratch or distroless for the runtime:
#   reqwest in this stack is rustls + rustls-native-certs, which reads the OS
#   trust store. scratch has none, so every HTTPS call to S3 fails at handshake.
#   Debian slim costs about 30 MB over scratch and keeps a shell for incident
#   work.
#
# Do not put --platform=$BUILDPLATFORM on these FROM lines. Each architecture
# of rust-base has to carry that architecture's rustc. The BUILDPLATFORM pin
# belongs on the *service* builder stage, so rustc stays native and only the
# linker (installed below for both GNU triples) targets the other arch.
ARG RUST_VERSION=1.98
ARG DEBIAN_SUITE=trixie

# --------------------------------------------------------------- toolchain --
FROM rust:${RUST_VERSION}-slim-${DEBIAN_SUITE} AS toolchain

# The official slim image already carries gcc, libc6-dev and ca-certificates,
# and installs rustup with --profile minimal, which has no clippy and no
# rustfmt. What is added here:
#   g++                      crates whose build.rs calls cc::Build::cpp(true).
#                            The slim image has the C compiler only, so a crate
#                            like custom-labels (vendored into dagentic, pulled
#                            in by the vortex feature and by its benchmark
#                            member) fails at the build-script step without it.
#                            g++ also brings the libstdc++ headers; the runtime
#                            half already has libstdc++6 to link against.
#   gcc/g++-*-linux-gnu      both GNU triples, so a --platform=$BUILDPLATFORM
#                            service build can cross-link without apt-get.
#   libc6-dev-*-cross        named explicitly because the cross gcc package
#                            only Recommends it. --no-install-recommends would
#                            leave it out, and ring's C then fails with
#                            "bits/libc-header-start.h: No such file or directory".
#                            glibc 2.41, same as the trixie runtime half.
#   pkg-config, libssl-dev   -sys crates probing for system libraries
#   zlib1g-dev               a few build.rs scripts probe for zlib
#   make, cmake              build scripts of C dependencies
#   git                      git = "..." dependencies and vendored submodules
#   lld                      faster linker; cargo-config.toml passes -fuse-ld=lld
#   python3                  occasional build.rs (not bindgen; clang stays out)
# Deliberately left out: clang / libclang-dev. Only bindgen users need it
# (rocksdb, rdkafka), it costs a few hundred MB, and a service builder stage
# can apt-get it in one line.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      g++ \
      gcc-x86-64-linux-gnu \
      gcc-aarch64-linux-gnu \
      g++-x86-64-linux-gnu \
      g++-aarch64-linux-gnu \
      libc6-dev-amd64-cross \
      libc6-dev-arm64-cross \
      pkg-config \
      libssl-dev \
      zlib1g-dev \
      make \
      cmake \
      git \
      lld \
      python3 \
 && rm -rf /var/lib/apt/lists/*

# clippy / rustfmt: so CI can lint on the same image.
# Both GNU linux stds: so a BUILDPLATFORM-pinned service build does not
# rustup target add at compile time (that download is easy to miss in a
# "why is Jenkins still compiling" log).
RUN rustup component add clippy rustfmt \
 && rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu

COPY cargo-config.toml /usr/local/cargo/config.toml

# Same uid as python-base / java-base / node-base. Default user stays root so a
# child Dockerfile can apt-get and mkdir without an extra USER dance.
# uid 10001 is above SYS_UID_MAX (999), so useradd --system warns. Ignore that.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

# Registry sources plus, when this arch is native, compiled rlibs for both GNU
# targets. Service images set CARGO_TARGET_DIR here so they reuse those rlibs
# instead of LLVM-ing DataFusion on every Jenkins job.
#
# PRECOMPILE=auto (default) compiles only when BUILDARCH=TARGETARCH. A Mac
# rust-push then cooks the arm64 image natively (~20-40 min extra) and skips
# the amd64 image, which would otherwise compile DataFusion under QEMU for
# hours. Cook the amd64 image on an amd64 node: make rust-push-cooked-amd64.
ARG BUILDARCH
ARG TARGETARCH
ARG PRECOMPILE=auto
ARG CARGO_JOBS=2
ENV CARGO_TERM_COLOR=always \
    CARGO_INCREMENTAL=0 \
    CARGO_NET_RETRY=10 \
    RUSTUP_MAX_RETRIES=10 \
    CARGO_BUILD_JOBS=${CARGO_JOBS} \
    CARGO_PROFILE_RELEASE_DEBUG=false \
    CARGO_TARGET_DIR=/opt/rust-cache \
    CC_x86_64_unknown_linux_gnu=x86_64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CXX_x86_64_unknown_linux_gnu=x86_64-linux-gnu-g++ \
    CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++

COPY warmup /opt/rust-warmup
RUN cargo fetch --locked --manifest-path /opt/rust-warmup/Cargo.toml
# Native triple only. Cooking the other GNU target as well doubled
# /opt/rust-cache (~5 GB) and a 20 GB Colima disk filled while unpacking
# the layer. Cross gcc and the other rustup target stay in the image so a
# BUILDPLATFORM-pinned service can still cross-link; those rlibs land in
# the service's per-TARGETARCH BuildKit cache after the first job.
RUN set -eux; \
    do_compile=0; \
    if [ "${PRECOMPILE}" = "1" ]; then do_compile=1; \
    elif [ "${PRECOMPILE}" = "auto" ] && [ "${BUILDARCH}" = "${TARGETARCH}" ]; then do_compile=1; \
    fi; \
    if [ "${do_compile}" != 1 ]; then \
      echo "skip precompile PRECOMPILE=${PRECOMPILE} BUILDARCH=${BUILDARCH} TARGETARCH=${TARGETARCH}"; \
      exit 0; \
    fi; \
    cargo build --release --locked --manifest-path /opt/rust-warmup/Cargo.toml; \
    touch /opt/rust-cache/.cooked; \
    du -sh /opt/rust-cache; \
    echo "rust-base rlibs ready"

LABEL org.opencontainers.image.title="rust-base" \
      org.opencontainers.image.description="Rust toolchain (clippy, rustfmt, both GNU linux targets, cross gcc, lld) plus a cargo-fetched and, when native, cargo-built DataFusion/Arrow graph. Build stage only, pair with rust-runtime."

# Smoke / default. Service builder stages override with cargo build.
CMD ["cargo", "--version"]

# ----------------------------------------------------------------- runtime --
FROM debian:${DEBIAN_SUITE}-slim AS runtime

# ca-certificates: rustls-native-certs and OpenSSL both read /etc/ssl/certs.
#   Without it, S3 over HTTPS fails with an unknown-issuer error.
# tzdata: chrono::Local resolves /etc/localtime. Without tzdata it falls back to
#   UTC silently, which surfaces later as wrong log and audit timestamps.
# Already in debian:trixie-slim, so not installed again: libgcc-s1 (every Rust
# binary links it) and libssl3t64 (OpenSSL 3.5, for a service that links it
# dynamically). Note the t64 suffix: Debian 13 renamed libssl3 in the 64-bit
# time_t transition, and `apt-get install libssl3` fails here.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    TZ=UTC

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
 && mkdir -p /app/logs \
 && chown app:app /app /app/logs

WORKDIR /app

LABEL org.opencontainers.image.title="rust-runtime" \
      org.opencontainers.image.description="Debian slim + ca-certificates + tzdata + uid 10001. Runtime half of rust-base, no Rust toolchain."

# Smoke / default. Service images override with CMD ["/usr/local/bin/<binary>"].
CMD ["cat", "/etc/os-release"]
