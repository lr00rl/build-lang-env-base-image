# python-base: CPython 3.12 + hashed FastAPI stack.
#
# From the repo root:
#   make python-lock python-audit python-build-local python-smoke
#   make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#
# Or from this directory: make lock && make build-local && make smoke
SHELL := /bin/bash

PY            ?= 3.12
SUITE         ?= trixie
VERSION       ?= $(shell date +%Y.%m).1
# Set on push. Empty on purpose: a clone must not push to someone else's registry.
REGISTRY      ?=
NAME          ?= python-base
IMAGE         := $(REGISTRY)/$(NAME)
TAG           := $(PY)-$(SUITE)-$(VERSION)
LOCAL_IMAGE   ?= $(NAME):local
# --load only works on a docker-driver builder. Colima: colima. Docker Desktop: desktop-linux.
LOCAL_BUILDER ?= $(shell docker buildx ls 2>/dev/null | awk 'NR>1 && $$2=="docker" { gsub(/\*$$/, "", $$1); print $$1; exit }')
MULTI_BUILDER ?= multiarch
PLATFORMS     ?= linux/amd64,linux/arm64

UV_COMPILE := uv pip compile --universal --python-version $(PY) --generate-hashes -q
BUILD_ARGS := --build-arg PYTHON_VERSION=$(PY) --build-arg DEBIAN_SUITE=$(SUITE) \
	--label org.opencontainers.image.version=$(TAG) \
	--label org.opencontainers.image.revision=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown) \
	--label org.opencontainers.image.created=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# Local --load tags. provenance/sbom off so single-arch tags stay one platform
# (BuildKit's default attestation wraps even a 1-arch build in a manifest list).
LOCAL_FLAGS := --provenance=false --sbom=false

.DEFAULT_GOAL := help
.PHONY: help lock upgrade audit build-local build-local-arm64 build-local-amd64 build-local-multi \
	smoke smoke-arm64 smoke-amd64 smoke-multi builder push digest require-registry require-builder

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-18s %s\n", $$1, $$2}'

lock: base.lock ## resolve base.in -> base.lock (universal + hashes)
base.lock: base.in
	$(UV_COMPILE) base.in -o base.lock

upgrade: ## re-resolve to the newest versions base.in allows
	$(UV_COMPILE) --upgrade base.in -o base.lock

audit: base.lock ## CVE scan of the lock
	uvx pip-audit --disable-pip --require-hashes -r base.lock

require-builder:
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }

build-local: base.lock require-builder ## native-arch image -> python-base:local
	docker buildx build --builder $(LOCAL_BUILDER) --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(LOCAL_IMAGE) .

build-local-arm64: base.lock require-builder ## arm64-only image -> python-base:local-arm64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-arm64 .

build-local-amd64: base.lock require-builder ## amd64-only image -> python-base:local-amd64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-amd64 .

# Dual-arch index. Colima's containerd image store can --load both platforms.
build-local-multi: base.lock require-builder ## dual-arch index -> python-base:local-multi
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64,linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-multi .

smoke: ## print arch, versions, and uid 10001
	docker run --rm $(LOCAL_IMAGE) sh -c 'uname -m && python --version && uv --version && uv pip check && python -c "import fastapi, starlette, pydantic, sqlalchemy; print(fastapi.__version__, starlette.__version__, pydantic.VERSION, sqlalchemy.__version__)"'
	docker run --rm --user app $(LOCAL_IMAGE) python -c "import os; print('uid', os.getuid())"
	docker image ls $(LOCAL_IMAGE)

smoke-arm64: ## smoke python-base:local-arm64 (uname must be aarch64)
	docker run --rm --platform linux/arm64 $(NAME):local-arm64 sh -c 'uname -m && python --version && uv pip check'
	@docker image inspect $(NAME):local-arm64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-amd64: ## smoke python-base:local-amd64 (uname must be x86_64)
	docker run --rm --platform linux/amd64 $(NAME):local-amd64 sh -c 'uname -m && python --version && uv pip check'
	@docker image inspect $(NAME):local-amd64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-multi: ## show both platforms on python-base:local-multi, then run each
	@docker image ls --tree $(NAME) | awk '/local-multi/,/^$$/'
	docker run --rm --platform linux/arm64 $(NAME):local-multi sh -c 'uname -m && python --version'
	docker run --rm --platform linux/amd64 $(NAME):local-multi sh -c 'uname -m && python --version'

builder: ## create the multi-arch (docker-container) builder once
	docker buildx inspect $(MULTI_BUILDER) >/dev/null 2>&1 || docker buildx create --name $(MULTI_BUILDER) --driver docker-container --bootstrap

require-registry:
	@test -n "$(REGISTRY)" || { echo "set REGISTRY, e.g. make push REGISTRY=ghcr.io/your-org"; exit 1; }

push: require-registry base.lock audit builder ## multi-arch build + push (requires REGISTRY)
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) -t $(IMAGE):$(PY)-$(SUITE) --push .
	@$(MAKE) --no-print-directory digest

digest: require-registry ## print tag@sha256 for service Dockerfiles
	@echo "$(IMAGE):$(TAG)@$$(crane digest $(IMAGE):$(TAG))"
