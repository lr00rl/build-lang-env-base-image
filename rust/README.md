# rust-base and rust-runtime

One Dockerfile, two targets, one pair of images. A Rust service compiles in the
first and ships in the second.

| Local tag | Target | Parent | What is inside |
| --- | --- | --- | --- |
| `rust-base:local` | `toolchain` | `rust:1.98-slim-trixie` | rustc / cargo 1.98, clippy, rustfmt, gcc, g++, pkg-config, cmake, make, git |
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

## What these images are not

Neither one is the application. There is no `COPY Cargo.toml`, no `cargo build`,
no `RUST_LOG`, no binary. `clang` / `libclang-dev` are left out too: only bindgen
users (rocksdb, rdkafka) need them, they cost a few hundred MB, and a service
builder stage can `apt-get` them in one line.

`g++` is in, unlike the official slim image, which ships the C compiler alone. A
build script that calls `cc::Build::cpp(true)` dies without it, and that is not
exotic: dagentic's vendored `custom-labels` crate compiles a C++ file that way.
Binaries built from it link `libstdc++` dynamically, which the runtime half
already carries.

Default `CMD`s are `cargo --version` and `cat /etc/os-release` so `make
rust-smoke` has something to run. Child images override them.

## Build

From the repo root:

```bash
make rust-build-local
make rust-smoke
make rust-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

Every build target writes both images at once. Single-arch and dual-arch local
tags work the same as the other languages:

```bash
make rust-build-local-arm64   # rust-base:local-arm64 + rust-runtime:local-arm64
make rust-build-local-amd64   # rust-base:local-amd64 + rust-runtime:local-amd64
make rust-build-local-multi   # :local-multi, linux/amd64 + linux/arm64
make rust-smoke-arm64 rust-smoke-amd64 rust-smoke-multi
```

From this directory: `make build-local && make smoke`.

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

These two base images are apt installs, so QEMU emulation costs a minute. A
service image is different: cross-building it emulated means compiling the whole
dependency graph under QEMU, which runs roughly an order of magnitude slower. A
DataFusion-sized workspace that takes 12 minutes natively can take two hours.

Build the service natively on each architecture and join the results:

```bash
docker buildx build --platform linux/arm64 -t $REG/svc:0.2.4-arm64 --push .   # on arm64
docker buildx build --platform linux/amd64 -t $REG/svc:0.2.4-amd64 --push .   # on an amd64 node
docker buildx imagetools create -t $REG/svc:0.2.4 $REG/svc:0.2.4-arm64 $REG/svc:0.2.4-amd64
```

If the cluster is amd64-only, the simpler answer is to build only
`--platform linux/amd64` on an amd64 build agent and skip the index entirely.

## Use it from a service

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BUILDER_IMAGE=rust-base:local
ARG RUNTIME_IMAGE=rust-runtime:local

FROM ${BUILDER_IMAGE} AS build
WORKDIR /src
COPY . .
# The cache mounts hold the crate registry and the target dir across builds, so
# only the changed crates recompile. Both live outside the layer, which is why
# the binary is copied to /out inside the same RUN: after it ends, /src/target
# is not visible any more.
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/src/target,sharing=locked \
    cargo build --release --locked -p yourapp \
 && install -Dm755 target/release/yourapp /out/yourapp

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
