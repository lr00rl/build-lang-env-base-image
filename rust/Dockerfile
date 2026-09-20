# syntax=docker/dockerfile:1.7
#
# Two images out of one file:
#   --target toolchain -> rust-base     rustc, cargo, clippy, rustfmt, a C toolchain
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
#   pkg-config, libssl-dev   -sys crates probing for system libraries
#   make, cmake              build scripts of C dependencies
#   git                      git = "..." dependencies and vendored submodules
# Deliberately left out: clang / libclang-dev. Only bindgen users need it
# (rocksdb, rdkafka), it costs a few hundred MB, and a service builder stage
# can apt-get it in one line.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      g++ \
      pkg-config \
      libssl-dev \
      make \
      cmake \
      git \
 && rm -rf /var/lib/apt/lists/*

# So CI can lint and build on the same image instead of pulling a second one.
RUN rustup component add clippy rustfmt

# CARGO_INCREMENTAL=0: a container build is one shot and throws the incremental
# cache away, so producing it only costs disk and link time.
# The retry counts are for flaky registry DNS inside build agents.
ENV CARGO_TERM_COLOR=always \
    CARGO_INCREMENTAL=0 \
    CARGO_NET_RETRY=10 \
    RUSTUP_MAX_RETRIES=10

# Same uid as python-base / java-base / node-base. Default user stays root so a
# child Dockerfile can apt-get and mkdir without an extra USER dance.
# uid 10001 is above SYS_UID_MAX (999), so useradd --system warns. Ignore that.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

LABEL org.opencontainers.image.title="rust-base" \
      org.opencontainers.image.description="Rust toolchain (clippy, rustfmt, cc, pkg-config, cmake) on Debian slim. Build stage only, pair with rust-runtime."

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
