# java-base: Eclipse Temurin 17 JDK on Ubuntu 22.04 (jammy).
#
# From the repo root:
#   make java-build-local java-smoke
#   make java-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#
# Or from this directory: make build-local && make smoke
SHELL := /bin/bash

JAVA          ?= 17
DISTRO        ?= jammy
VERSION       ?= $(shell date +%Y.%m).1
REGISTRY      ?=
NAME          ?= java-base
IMAGE         := $(REGISTRY)/$(NAME)
TAG           := $(JAVA)-jdk-$(DISTRO)-$(VERSION)
LOCAL_IMAGE   ?= $(NAME):local
LOCAL_BUILDER ?= $(shell docker buildx ls 2>/dev/null | awk 'NR>1 && $$2=="docker" { gsub(/\*$$/, "", $$1); print $$1; exit }')
MULTI_BUILDER ?= multiarch
PLATFORMS     ?= linux/amd64,linux/arm64

BUILD_ARGS := --build-arg JAVA_VERSION=$(JAVA) --build-arg DISTRO=$(DISTRO) \
	--label org.opencontainers.image.version=$(TAG) \
	--label org.opencontainers.image.revision=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown) \
	--label org.opencontainers.image.created=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LOCAL_FLAGS := --provenance=false --sbom=false

.DEFAULT_GOAL := help
.PHONY: help build-local build-local-arm64 build-local-amd64 build-local-multi \
	smoke smoke-arm64 smoke-amd64 smoke-multi builder push digest require-registry require-builder

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-18s %s\n", $$1, $$2}'

require-builder:
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }

build-local: require-builder ## native-arch image -> java-base:local
	docker buildx build --builder $(LOCAL_BUILDER) --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(LOCAL_IMAGE) .

# Three local tags: one platform each, plus a dual-arch index.
# provenance/sbom off so the single-arch tags stay one platform.
build-local-arm64: require-builder ## arm64-only image -> java-base:local-arm64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-arm64 .

build-local-amd64: require-builder ## amd64-only image -> java-base:local-amd64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-amd64 .

build-local-multi: require-builder ## dual-arch index -> java-base:local-multi
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64,linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):local-multi .

smoke: ## print arch, java -version, JAVA_HOME, and uid 10001
	docker run --rm $(LOCAL_IMAGE) sh -c 'uname -m && java -version && echo JAVA_HOME=$$JAVA_HOME'
	docker run --rm --user app $(LOCAL_IMAGE) sh -c 'id && java -version'
	docker image ls $(LOCAL_IMAGE)

smoke-arm64: ## smoke java-base:local-arm64 (uname must be aarch64)
	docker run --rm --platform linux/arm64 $(NAME):local-arm64 sh -c 'uname -m && java -version && echo JAVA_HOME=$$JAVA_HOME'
	docker run --rm --platform linux/arm64 --user app $(NAME):local-arm64 sh -c 'id && java -version'
	@docker image inspect $(NAME):local-arm64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-amd64: ## smoke java-base:local-amd64 (uname must be x86_64)
	docker run --rm --platform linux/amd64 $(NAME):local-amd64 sh -c 'uname -m && java -version && echo JAVA_HOME=$$JAVA_HOME'
	docker run --rm --platform linux/amd64 --user app $(NAME):local-amd64 sh -c 'id && java -version'
	@docker image inspect $(NAME):local-amd64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-multi: ## show both platforms on java-base:local-multi, then run each
	@docker image ls --tree $(NAME) | awk '/local-multi/,/^$$/'
	docker run --rm --platform linux/arm64 $(NAME):local-multi sh -c 'uname -m && java -version'
	docker run --rm --platform linux/amd64 $(NAME):local-multi sh -c 'uname -m && java -version'

builder: ## create the multi-arch (docker-container) builder once
	docker buildx inspect $(MULTI_BUILDER) >/dev/null 2>&1 || docker buildx create --name multiarch --driver docker-container --bootstrap

require-registry:
	@test -n "$(REGISTRY)" || { echo "set REGISTRY, e.g. make push REGISTRY=ghcr.io/your-org"; exit 1; }

push: require-registry builder ## multi-arch build + push (requires REGISTRY)
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) -t $(IMAGE):$(JAVA)-jdk-$(DISTRO) --push .
	@$(MAKE) --no-print-directory digest

digest: require-registry ## print tag@sha256 for service Dockerfiles
	@echo "$(IMAGE):$(TAG)@$$(crane digest $(IMAGE):$(TAG))"
