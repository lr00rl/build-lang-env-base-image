# py-base build / test / push
#   make lock audit build-local smoke            # local, native arch
#   make build-local-amd64                       # optional: amd64 via emulation
#   make push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
SHELL := /bin/bash

PY            ?= 3.12
SUITE         ?= trixie
VERSION       ?= $(shell date +%Y.%m).1
# Set on push, e.g. ghcr.io/your-org or registry.example.com/team
REGISTRY      ?=
NAME          ?= py-base
IMAGE         := $(REGISTRY)/$(NAME)
TAG           := $(PY)-$(SUITE)-$(VERSION)
LOCAL_IMAGE   ?= $(NAME):local
# docker-driver builder is required for --load. Colima names it colima;
# Docker Desktop names it desktop-linux. Override if auto-detect is wrong.
LOCAL_BUILDER ?= $(shell docker buildx ls 2>/dev/null | awk 'NR>1 && $$2=="docker" { gsub(/\*$$/, "", $$1); print $$1; exit }')
MULTI_BUILDER ?= multiarch
PLATFORMS     ?= linux/amd64,linux/arm64

UV_COMPILE := uv pip compile --universal --python-version $(PY) --generate-hashes -q
BUILD_ARGS := --build-arg PYTHON_VERSION=$(PY) --build-arg DEBIAN_SUITE=$(SUITE) \
	--label org.opencontainers.image.version=$(TAG) \
	--label org.opencontainers.image.revision=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown) \
	--label org.opencontainers.image.created=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

.DEFAULT_GOAL := help
.PHONY: help lock upgrade audit build-local build-local-amd64 smoke builder push digest require-registry

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

lock: base.lock ## resolve base.in -> base.lock (universal + hashes)
base.lock: base.in
	$(UV_COMPILE) base.in -o base.lock

upgrade: ## re-resolve to the newest versions base.in allows
	$(UV_COMPILE) --upgrade base.in -o base.lock

audit: base.lock ## CVE scan of the lock
	uvx pip-audit --disable-pip --require-hashes -r base.lock

build-local: base.lock ## native-arch image -> local docker (py-base:local)
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }
	docker buildx build --builder $(LOCAL_BUILDER) --load $(BUILD_ARGS) -t $(LOCAL_IMAGE) .

build-local-amd64: base.lock ## amd64 image via emulation (py-base:local-amd64)
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64 --load $(BUILD_ARGS) -t $(NAME):local-amd64 .

smoke: ## sanity-check the local image
	docker run --rm $(LOCAL_IMAGE) sh -c 'uname -m && python --version && uv --version && uv pip check && python -c "import fastapi, starlette, pydantic, sqlalchemy; print(fastapi.__version__, starlette.__version__, pydantic.VERSION, sqlalchemy.__version__)"'
	docker run --rm --user app $(LOCAL_IMAGE) python -c "import os; print('uid', os.getuid())"
	docker image ls $(LOCAL_IMAGE)

builder: ## create the multi-arch (docker-container) builder once
	docker buildx inspect $(MULTI_BUILDER) >/dev/null 2>&1 || docker buildx create --name $(MULTI_BUILDER) --driver docker-container --bootstrap

require-registry:
	@test -n "$(REGISTRY)" || { echo "set REGISTRY, e.g. make push REGISTRY=ghcr.io/your-org"; exit 1; }

push: require-registry base.lock audit builder ## multi-arch build + push (requires REGISTRY)
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) -t $(IMAGE):$(PY)-$(SUITE) --push .
	@$(MAKE) --no-print-directory digest

digest: require-registry ## print the pinned reference for project Dockerfiles
	@echo "$(IMAGE):$(TAG)@$$(crane digest $(IMAGE):$(TAG))"
