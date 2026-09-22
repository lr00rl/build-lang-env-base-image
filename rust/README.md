# rust-base and rust-runtime

One Dockerfile, two targets, one pair of images. A Rust service compiles in the
first and ships in the second.

| Local tag | Target | Parent | What is inside |
| --- | --- | --- | --- |
| `rust-base:local` | `toolchain` | `rust:1.98-slim-trixie` | rustc / cargo 1.98, clippy, rustfmt, gcc, g++, both GNU-linux cross gcc/g++, both rustup GNU targets, lld, pkg-config, cmake, make, git, python3, a cargo-fetched DataFusion/Arrow graph, and compiled rlibs for both GNU triples under `/opt/rust-cache` |
| `rust-runtime:local` | `runtime` | `debian:trixie-slim` | ca-certificates, tzdata, uid 10001, `/app` |

Both are built for `linux/amd64` and `linux/arm64`.

## Why two images

python-base is both the build image and the runtime, because a Python service
runs on the interpreter that installed its dependencies. Rust does not work that
way: the output is one binary, and cargo plus the standard library sources are
about 1.5 GB that the cluster would pull on every rollout for nothing.

They stay in one file because the pair has to agree on libc. A binary linked
against trixie's glibc 2.41 will not start on a bookworm runtime; it dies at
exec with `GLIBC_2.41 not found`. `DEBIAN_SUITE` drives both stages, so bumping
the suite bumps both or neither.

## Why Debian, not Alpine

Crates that compile C (`zstd-sys`, `ring`, `aws-lc-sys`) need a full musl
toolchain on Alpine, and musl's allocator is markedly slower on allocation-heavy
work such as DataFusion query execution. A service that genuinely wants a static
binary adds the target in its own builder stage (`rustup target add
x86_64-unknown-linux-musl`) rather than changing the base for everyone.

scratch and distroless were rejected for the runtime for a narrower reason: the
usual TLS path here is rustls with `rustls-native-certs`, which reads the OS
trust store. On scratch there is none and every HTTPS call to S3 fails at the
handshake. Debian slim costs roughly 30 MB over scratch and keeps a shell for
incident work.

`debian:trixie-slim` already carries `libgcc-s1` (every Rust binary links it) and
`libssl3t64` (OpenSSL 3.5, for a service that links OpenSSL dynamically), so
neither is installed again. Note the `t64` suffix: Debian 13 renamed the package
in the 64-bit `time_t` transition, and `apt-get install libssl3` fails on trixie.

## What is in rust-base, and what is not

This is not the application. There is no service `COPY`, no `RUST_LOG`. There is
a tiny `warmup/` crate whose versions are pinned to dagentic's `Cargo.lock`.
`cargo fetch --locked` puts that graph in `CARGO_HOME/registry`. A `cook`
stage then `cargo build --release --target` both GNU triples on
`$BUILDPLATFORM` (native rustc, cross gcc for the other half) and copies only
those `target/<triple>` trees into every rust-base platform. Host proc-macros
stay out: they cannot run on the other Jenkins arch. That is the rust analogue
of python-base installing the FastAPI lock: a cold Jenkins agent should not
wait on crates.io, or LLVM, for the same hundreds of crates every build.

`PRECOMPILE=0` skips the cook (fetch only). Do not run the cook itself under
QEMU. The Dockerfile pins cook to `$BUILDPLATFORM`, so a Mac multi-arch
`rust-push` compiles DataFusion once on arm64 and `COPY --from`s the rlibs
onto the amd64 image. The amd64 half still runs apt and `cargo fetch` under
QEMU; that is minutes, not hours.

`clang` / `libclang-dev` stay out: only bindgen users (rocksdb, rdkafka) need
them, they cost a few hundred MB, and a service builder stage can `apt-get`
them in one line.

`g++` is in, unlike the official slim image, which ships the C compiler alone. A
build script that calls `cc::Build::cpp(true)` dies without it, and that is not
exotic: dagentic's vendored `custom-labels` crate compiles a C++ file that way.
Binaries built from it link `libstdc++` dynamically, which the runtime half
already carries.

Both GNU linux triples are in as well (`x86_64-unknown-linux-gnu` and
`aarch64-unknown-linux-gnu`, plus `gcc`/`g++`/`libc6-dev` for each). A service
builder that pins `--platform=$BUILDPLATFORM` then only has to pass
`cargo build --target <triple>`; it does not apt-get a cross compiler. The
linker wiring lives in `/usr/local/cargo/config.toml` (`linker`, `ar`, and
`-fuse-ld=lld`). Do not pin `$BUILDPLATFORM` on the `toolchain-apt` FROM:
each architecture of this image has to carry that architecture's rustc. The
`cook` stage is the exception: it is pinned so a multi-arch push compiles
the rlib graph once on the build machine.

Default `CMD`s are `cargo --version` and `cat /etc/os-release` so `make
rust-smoke` has something to run. Child images override them.

## Build

From the repo root:

```bash
make rust-lock
make rust-build-local
make rust-smoke
make rust-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

`make rust-lock` regenerates `rust/warmup/Cargo.lock` after you edit
`rust/warmup/Cargo.toml`. Pin top-level versions to the live service's
`Cargo.lock` (dagentic today) so the fetched graph actually hits.

`make rust-push` cooks both GNU triples on the host (`make cook-rlibs`,
output in `rust/.rlib-out/`) and overlays those trees onto the existing
Harbor toolchain for linux/amd64 and linux/arm64. LLVM writes to the Mac
disk so Colima's 20 GB image store is not asked to hold two triples plus a
QEMU fetch. Host proc-macros stay out of the overlay; Jenkins rebuilds
those for amd64 and reuses the target rlibs.

The Dockerfile still has a `cook` stage (`PRECOMPILE=0` skips it) for a
machine with enough image-store disk. On this Mac that path filled the
volume; do not use it here.

Service Dockerfiles seed a per-arch BuildKit cache from
`/opt/rust-cache/<triple>` rather than compiling into `/opt/rust-cache`.
Do not cache-mount `/usr/local/cargo/registry`.

To rebuild one platform of the *toolchain* without touching the other:

```bash
make rust-push-cooked-arm64 REGISTRY=harbor.openjobs-ai.com/openjobs-ai \
  NAME=rust CARGO_JOBS=2
make rust-push-cooked-amd64 REGISTRY=harbor.openjobs-ai.com/openjobs-ai \
  NAME=rust CARGO_JOBS=8
make rust-merge-cooked REGISTRY=harbor.openjobs-ai.com/openjobs-ai NAME=rust
```

Every build target writes both images at once. Single-arch and dual-arch local
tags work the same as the other languages:

```bash
make rust-build-local-arm64   # rust-base:local-arm64 + rust-runtime:local-arm64
make rust-build-local-amd64   # rust-base:local-amd64 + rust-runtime:local-amd64
make rust-build-local-multi   # :local-multi, linux/amd64 + linux/arm64
make rust-smoke-arm64 rust-smoke-amd64 rust-smoke-multi
```

From this directory: `make lock && make build-local && make smoke`.

`--load` needs a docker-driver builder (Colima: `colima`, Docker Desktop:
`desktop-linux`). Multi-arch `--push` uses the `multiarch` docker-container
builder (`make rust-builder` creates it). Do not `docker tag` a native arm64
image and push it under the dual-arch name: amd64 nodes then fail with
`exec format error`.

`push` writes four tags: `$REGISTRY/rust-base:1.98-trixie-2026.09.1` and
`:1.98-trixie`, `$REGISTRY/rust-runtime:trixie-2026.09.1` and `:trixie`. The
runtime tag carries no Rust version because there is no Rust in it. To reuse an
existing registry repo name, pass `NAME=` and `RT_NAME=`.

`RUST` and `SUITE` are Makefile and build args: `make rust-build-local RUST=1.97`.
Confirm the Hub tag exists for both platforms first.

## Building a service image for the other architecture

The base images are apt + rustup + `cargo fetch` on each platform, plus one
native cook of both GNU rlib trees. QEMU on the foreign half of `rust-push`
is therefore a few minutes, not hours. A service image is different:
cross-building it emulated means compiling the whole dependency graph under
QEMU, which runs roughly an order of magnitude slower. A DataFusion-sized
workspace that takes 12 minutes natively can take two or three hours and still
be in the dependency graph.

The service Dockerfile pins the *builder* to the host and cross-compiles:

```dockerfile
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS build
ARG BUILDARCH
ARG TARGETARCH
```

rustc stays native. Only the linker, and the C in ring / zstd-sys / liblzma-sys,
target the other architecture. rust-base already has those compilers.

If the cluster is amd64-only, build only `--platform linux/amd64` on an amd64
agent and skip the index. Native-per-arch and `docker buildx imagetools create`
still works if you would rather not cross-link.

## Use it from a service

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BUILDER_IMAGE=rust-base:local
ARG RUNTIME_IMAGE=rust-runtime:local

FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS build
ARG BUILDARCH
ARG TARGETARCH
WORKDIR /src
ARG CARGO_JOBS=2
ENV CARGO_BUILD_JOBS=${CARGO_JOBS} \
    CARGO_PROFILE_RELEASE_DEBUG=false
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && printf 'fn main() {}\n' > src/main.rs
# Dummy sources, then real COPY . ., so lockfile-stable rebuilds skip DataFusion.
# Seed /opt/rust-cache into a per-arch cache; do not compile into /opt/rust-cache
# (layer bloat) and do not cache-mount the registry (hides the fetch).
RUN --mount=type=cache,id=yourapp-cargo-${TARGETARCH},target=/cache/target \
    set -eux; \
    case "${TARGETARCH}" in \
      amd64) triple=x86_64-unknown-linux-gnu ;; \
      arm64) triple=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ -f /opt/rust-cache/.cooked ] && [ -d "/opt/rust-cache/${triple}" ]; then \
      if [ ! -f /cache/target/.seeded ] \
         || [ ! -d "/cache/target/${triple}" ] \
         || [ /opt/rust-cache/.cooked -nt /cache/target/.seeded ]; then \
        mkdir -p /cache/target; \
        rm -rf "/cache/target/${triple}"; \
        cp -a "/opt/rust-cache/${triple}" "/cache/target/${triple}"; \
        touch /cache/target/.seeded; \
      fi; \
    fi; \
    export CARGO_TARGET_DIR=/cache/target; \
    cargo build --release --locked -p yourapp --target "${triple}"
COPY . .
RUN --mount=type=cache,id=yourapp-cargo-${TARGETARCH},target=/cache/target \
    set -eux; \
    export CARGO_TARGET_DIR=/cache/target; \
    case "${TARGETARCH}" in \
      amd64) triple=x86_64-unknown-linux-gnu ;; \
      arm64) triple=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    cargo clean --release --locked -p yourapp --target "${triple}"; \
    cargo build --release --locked -p yourapp --target "${triple}"; \
    install -Dm755 "/cache/target/${triple}/release/yourapp" /out/yourapp

FROM ${RUNTIME_IMAGE}
COPY --from=build /out/yourapp /usr/local/bin/yourapp
USER app
EXPOSE 8080
CMD ["/usr/local/bin/yourapp"]
```

`ARG BUILDER_IMAGE` / `ARG RUNTIME_IMAGE` must sit above the `FROM` lines; that
is the only place Docker lets an ARG reach `FROM`.

`--locked` makes the build fail instead of silently resolving a newer dependency
than `Cargo.lock` records. Commit the lock file for anything that gets deployed.

Cap the compile parallelism by memory, not by core count. One rustc peaks well
over a gigabyte on a large crate such as `datafusion-physical-plan`, so six of
them in a 4 GB VM reach the kernel OOM killer, which does not stop at cargo: it
can take the Docker daemon's socket forwarder with it and leave `docker`
unreachable until the VM restarts. An `ARG CARGO_JOBS` wired to
`ENV CARGO_BUILD_JOBS` makes that one build flag instead of a code change.

If the release profile keeps full debug info (`[profile.release] debug = true`,
common in a repo that profiles locally), set
`ENV CARGO_PROFILE_RELEASE_DEBUG=false` in the builder stage. It is worth
hundreds of megabytes in the binary and a good share of the link time, and it
does not touch the repo's Cargo.toml.

Keep secrets out of the image. Credentials belong in the environment or in a
mounted file, never in a `COPY .env`.
