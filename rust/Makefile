# rust-base + rust-runtime: one Dockerfile, two targets.
#
# From the repo root:
#   make rust-build-local rust-smoke
#   make rust-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#
# Or from this directory: make build-local && make smoke
#
# Every build target writes both images. They are a pair: the runtime has to
# come from the same DEBIAN_SUITE as the toolchain that linked the binary.
SHELL := /bin/bash

RUST          ?= 1.98
SUITE         ?= trixie
VERSION       ?= $(shell date +%Y.%m).1
# Set on push. Empty on purpose: a clone must not push to someone else's registry.
REGISTRY      ?=
NAME          ?= rust-base
RT_NAME       ?= rust-runtime
IMAGE         := $(REGISTRY)/$(NAME)
RT_IMAGE      := $(REGISTRY)/$(RT_NAME)
TAG           := $(RUST)-$(SUITE)-$(VERSION)
# The runtime has no Rust in it, so its tag carries the Debian suite only.
RT_TAG        := $(SUITE)-$(VERSION)
LOCAL_IMAGE   ?= $(NAME):local
RT_LOCAL      ?= $(RT_NAME):local
# --load only works on a docker-driver builder. Colima: colima. Docker Desktop: desktop-linux.
LOCAL_BUILDER ?= $(shell docker buildx ls 2>/dev/null | awk 'NR>1 && $$2=="docker" { gsub(/\*$$/, "", $$1); print $$1; exit }')
MULTI_BUILDER ?= multiarch
PLATFORMS     ?= linux/amd64,linux/arm64

PRECOMPILE   ?= auto
CARGO_JOBS   ?= 2

BUILD_ARGS := --build-arg RUST_VERSION=$(RUST) --build-arg DEBIAN_SUITE=$(SUITE) \
	--build-arg PRECOMPILE=$(PRECOMPILE) --build-arg CARGO_JOBS=$(CARGO_JOBS) \
	--label org.opencontainers.image.version=$(TAG) \
	--label org.opencontainers.image.revision=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown) \
	--label org.opencontainers.image.created=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# Local --load tags. provenance/sbom off so single-arch tags stay one platform
# (BuildKit's default attestation wraps even a 1-arch build in a manifest list).
LOCAL_FLAGS := --provenance=false --sbom=false

BUILD := docker buildx build --builder $(LOCAL_BUILDER) --load $(LOCAL_FLAGS) $(BUILD_ARGS)

.DEFAULT_GOAL := help
.PHONY: help lock build-local build-local-arm64 build-local-amd64 build-local-multi \
	smoke smoke-arm64 smoke-amd64 smoke-multi builder push \
	push-cooked-amd64 push-cooked-arm64 merge-cooked digest \
	require-registry require-builder

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-18s %s\n", $$1, $$2}'

lock: ## remind how warmup/Cargo.lock is maintained (do not generate-lockfile)
	@echo "warmup/Cargo.lock is the reachable subset of dagentic Cargo.lock."
	@echo "cargo generate-lockfile floats transitives and those rlibs miss dagentic."

require-builder:
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }

build-local: warmup/Cargo.lock require-builder ## native-arch pair -> rust-base:local + rust-runtime:local
	$(BUILD) --target toolchain -t $(LOCAL_IMAGE) .
	$(BUILD) --target runtime   -t $(RT_LOCAL) .

build-local-arm64: warmup/Cargo.lock require-builder ## arm64-only pair -> :local-arm64
	$(BUILD) --platform linux/arm64 --target toolchain -t $(NAME):local-arm64 .
	$(BUILD) --platform linux/arm64 --target runtime   -t $(RT_NAME):local-arm64 .

build-local-amd64: warmup/Cargo.lock require-builder ## amd64-only pair -> :local-amd64
	$(BUILD) --platform linux/amd64 --target toolchain -t $(NAME):local-amd64 .
	$(BUILD) --platform linux/amd64 --target runtime   -t $(RT_NAME):local-amd64 .

# Dual-arch index. Colima's containerd image store can --load both platforms.
build-local-multi: warmup/Cargo.lock require-builder ## dual-arch index -> :local-multi
	$(BUILD) --platform linux/amd64,linux/arm64 --target toolchain -t $(NAME):local-multi .
	$(BUILD) --platform linux/amd64,linux/arm64 --target runtime   -t $(RT_NAME):local-multi .

smoke: ## print arch, toolchain, both GNU targets, cross gcc, lld, fetched crates
	docker run --rm $(LOCAL_IMAGE) sh -c 'set -e; uname -m; rustc --version; cargo --version; cargo clippy --version; cargo fmt --version; rustup target list --installed; x86_64-linux-gnu-gcc --version | head -1; aarch64-linux-gnu-gcc --version | head -1; x86_64-linux-gnu-g++ --version | head -1; aarch64-linux-gnu-g++ --version | head -1; ld.lld --version | head -1; python3 --version; test -f /usr/local/cargo/config.toml; test -d /usr/local/cargo/registry/src; test -f /opt/rust-warmup/Cargo.lock; echo CARGO_TARGET_DIR=$$CARGO_TARGET_DIR; ls /opt/rust-cache/.cooked'
	docker run --rm $(RT_LOCAL) sh -c 'uname -m && . /etc/os-release && echo "$$PRETTY_NAME" && ls -l /etc/ssl/certs/ca-certificates.crt && ldconfig -p | grep -c libgcc_s'
	docker run --rm --user app $(RT_LOCAL) id
	docker image ls $(NAME):local
	docker image ls $(RT_NAME):local

smoke-arm64: ## smoke the arm64 pair (uname must be aarch64)
	docker run --rm --platform linux/arm64 $(NAME):local-arm64 sh -c 'uname -m && rustc --version'
	docker run --rm --platform linux/arm64 $(RT_NAME):local-arm64 sh -c 'uname -m && . /etc/os-release && echo "$$PRETTY_NAME"'
	@docker image inspect $(NAME):local-arm64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'
	@docker image inspect $(RT_NAME):local-arm64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-amd64: ## smoke the amd64 pair (uname must be x86_64)
	docker run --rm --platform linux/amd64 $(NAME):local-amd64 sh -c 'uname -m && rustc --version'
	docker run --rm --platform linux/amd64 $(RT_NAME):local-amd64 sh -c 'uname -m && . /etc/os-release && echo "$$PRETTY_NAME"'
	@docker image inspect $(NAME):local-amd64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'
	@docker image inspect $(RT_NAME):local-amd64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-multi: ## show both platforms on the :local-multi pair, then run each
	@docker image ls --tree $(NAME) | awk '/local-multi/,/^$$/'
	docker run --rm --platform linux/arm64 $(NAME):local-multi sh -c 'uname -m && rustc --version'
	docker run --rm --platform linux/amd64 $(NAME):local-multi sh -c 'uname -m && rustc --version'
	docker run --rm --platform linux/arm64 $(RT_NAME):local-multi uname -m
	docker run --rm --platform linux/amd64 $(RT_NAME):local-multi uname -m

builder: ## create the multi-arch (docker-container) builder once
	docker buildx inspect $(MULTI_BUILDER) >/dev/null 2>&1 || docker buildx create --name $(MULTI_BUILDER) --driver docker-container --bootstrap

require-registry:
	@test -n "$(REGISTRY)" || { echo "set REGISTRY, e.g. make push REGISTRY=ghcr.io/your-org"; exit 1; }

push: warmup/Cargo.lock require-registry builder ## multi-arch build + push of both images (requires REGISTRY)
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true --target toolchain \
	  -t $(IMAGE):$(TAG) -t $(IMAGE):$(RUST)-$(SUITE) --push .
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true --target runtime \
	  -t $(RT_IMAGE):$(RT_TAG) -t $(RT_IMAGE):$(SUITE) --push .
	@$(MAKE) --no-print-directory digest

# Native cook of /opt/rust-cache for both GNU targets. PRECOMPILE=auto on a
# Mac skips the amd64 half (QEMU would compile DataFusion for hours). Cook
# each arch on a machine of that arch, then merge:
#   make rust-push-cooked-arm64 REGISTRY=... NAME=rust
#   make rust-push-cooked-amd64 REGISTRY=... NAME=rust   # on the Jenkins node
#   make rust-merge-cooked      REGISTRY=... NAME=rust
push-cooked-amd64: warmup/Cargo.lock require-registry builder ## native amd64 rust-base with precompiled rlibs
	docker buildx build --builder $(MULTI_BUILDER) --platform linux/amd64 \
	  --build-arg RUST_VERSION=$(RUST) --build-arg DEBIAN_SUITE=$(SUITE) \
	  --build-arg PRECOMPILE=1 --build-arg CARGO_JOBS=$(CARGO_JOBS) \
	  --provenance=mode=max --sbom=true --target toolchain \
	  -t $(IMAGE):$(RUST)-$(SUITE)-amd64 --push .

push-cooked-arm64: warmup/Cargo.lock require-registry builder ## native arm64 rust-base with precompiled rlibs
	docker buildx build --builder $(MULTI_BUILDER) --platform linux/arm64 \
	  --build-arg RUST_VERSION=$(RUST) --build-arg DEBIAN_SUITE=$(SUITE) \
	  --build-arg PRECOMPILE=1 --build-arg CARGO_JOBS=$(CARGO_JOBS) \
	  --provenance=mode=max --sbom=true --target toolchain \
	  -t $(IMAGE):$(RUST)-$(SUITE)-arm64 --push .

merge-cooked: require-registry ## index from the two cooked single-arch rust-base tags
	docker buildx imagetools create \
	  -t $(IMAGE):$(TAG) -t $(IMAGE):$(RUST)-$(SUITE) \
	  $(IMAGE):$(RUST)-$(SUITE)-amd64 \
	  $(IMAGE):$(RUST)-$(SUITE)-arm64
	@$(MAKE) --no-print-directory digest

digest: require-registry ## print tag@sha256 for service Dockerfiles
	@echo "$(IMAGE):$(TAG)@$$(crane digest $(IMAGE):$(TAG))"
	@echo "$(RT_IMAGE):$(RT_TAG)@$$(crane digest $(RT_IMAGE):$(RT_TAG))"
