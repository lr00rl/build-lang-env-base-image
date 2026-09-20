# build-lang-env-base-image

Shared **language runtime** images, one directory per language. Each image is a parent: service Dockerfiles `FROM` it, then add the app. Builds are multi-arch (`linux/amd64` and `linux/arm64`) through Docker Buildx.

| Directory | Local tag | Parent | What is inside |
| --- | --- | --- | --- |
| [`python/`](python/README.md) | `python-base:local` | `python:3.12-slim-trixie` | CPython 3.12, `uv`, hashed FastAPI / SQLAlchemy / aiomysql stack |
| [`java/`](java/README.md) | `java-base:local` | `eclipse-temurin:17-jdk-jammy` | Temurin 17 JDK on Ubuntu 22.04 |
| [`node/`](node/README.md) | `node-base:18-alpine` / `20-alpine` / `22-alpine` | official `node:<N>-alpine` | Node 18, 20, and 22 on Alpine, uid 10001 |
| [`rust/`](rust/README.md) | `rust-base:local` + `rust-runtime:local` | `rust:1.98-slim-trixie` / `debian:trixie-slim` | Rust 1.98 toolchain with clippy, rustfmt and a C toolchain, plus the matching runtime half |

Rust is the one language that ships two images. A Rust service compiles against `rust-base` and deploys on `rust-runtime`, which holds no toolchain; see [`rust/README.md`](rust/README.md) for why they have to move together.

There is no default registry. `make python-push` / `make java-push` / `make node-push` / `make rust-push` require `REGISTRY=...` so a clone cannot push to someone else's repo.

## Make targets

From this directory:

```bash
make help

make python-lock python-audit python-build-local python-smoke
make python-build-local-arm64 python-build-local-amd64 python-build-local-multi
make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1

make java-build-local java-smoke
make java-build-local-arm64 java-build-local-amd64 java-build-local-multi
make java-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1

make node-build-versions node-smoke-versions
make node-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1 NODE=20

make rust-build-local rust-smoke
make rust-build-local-arm64 rust-build-local-amd64 rust-build-local-multi
make rust-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

`make python-<target>` is `make -C python <target>`. Same for `java-`, `node-`, and `rust-`. You can also `cd` into any of those directories and run the short names (`make build-local`).

`--load` (local images) needs a **docker-driver** builder: `docker buildx ls`. Colima names it `colima`; Docker Desktop names it `desktop-linux`. The language Makefiles pick the first docker-driver builder they see. `--push` of two platforms needs a docker-container builder named `multiarch` (any language's `-builder` target creates it once). That builder cannot `--load` a local tag.

Do not retag a single-arch local image and push it as the dual-arch name. amd64 nodes then fail with `exec format error`.

## Shared conventions

Each image creates a system user `app` with uid/gid **10001**. Default user stays **root** so a child Dockerfile can `chmod` / `mkdir` without flipping `USER`. Child images that want the unprivileged user write `USER app` after those steps.

None of these images copies application code, `.env` files, or heap / profile settings. Those belong in the service Dockerfile and in runtime config.

Base images are apt installs, so cross-building them under QEMU is cheap. A compiled-language *service* image is not: building a Rust service for the other architecture through emulation is roughly an order of magnitude slower than native. Build those on a native agent per architecture and join the two tags with `docker buildx imagetools create`.

## License

Add a license file before you rely on GitHub's public-repo defaults. This tree does not ship one yet.
