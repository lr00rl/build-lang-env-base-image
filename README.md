# build-lang-env-base-image

Shared **language runtime** images, one directory per language. Each image is a parent: service Dockerfiles `FROM` it, then add the app. Builds are multi-arch (`linux/amd64` and `linux/arm64`) through Docker Buildx.

| Directory | Local tag | Parent | What is inside |
| --- | --- | --- | --- |
| [`python/`](python/README.md) | `python-base:local` | `python:3.12-slim-trixie` | CPython 3.12, `uv`, hashed FastAPI / SQLAlchemy / aiomysql stack |
| [`java/`](java/README.md) | `java-base:local` | `eclipse-temurin:17-jdk-jammy` | Temurin 17 JDK on Ubuntu 22.04 |

There is no default registry. `make python-push` / `make java-push` require `REGISTRY=...` so a clone cannot push to someone else's repo.

## Make targets

From this directory:

```bash
make help

make python-lock python-audit python-build-local python-smoke
make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1

make java-build-local java-smoke
make java-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
```

`make python-<target>` is `make -C python <target>`. Same for `java-`. You can also `cd python` or `cd java` and run the short names (`make build-local`).

`--load` (local images) needs a **docker-driver** builder: `docker buildx ls`. Colima names it `colima`; Docker Desktop names it `desktop-linux`. The language Makefiles pick the first docker-driver builder they see. `--push` of two platforms needs a docker-container builder named `multiarch` (`make python-builder` or `make java-builder` creates it once). That builder cannot `--load` a local tag.

Do not retag a single-arch local image and push it as the dual-arch name. amd64 nodes then fail with `exec format error`.

## Shared conventions

Both images create a system user `app` with uid/gid **10001**. Default user stays **root** so a child Dockerfile can `chmod` / `mkdir` without flipping `USER`. Child images that want the unprivileged user write `USER app` after those steps.

Neither image copies application code, `.env` files, or heap / profile settings. Those belong in the service Dockerfile and in runtime config.

## License

Add a license file before you rely on GitHub's public-repo defaults. This tree does not ship one yet.
