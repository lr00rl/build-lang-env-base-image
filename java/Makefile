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

.DEFAULT_GOAL := help
.PHONY: help build-local build-local-amd64 smoke builder push digest require-registry require-builder

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-18s %s\n", $$1, $$2}'

require-builder:
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }

build-local: require-builder ## native-arch image -> java-base:local
	docker buildx build --builder $(LOCAL_BUILDER) --load $(BUILD_ARGS) -t $(LOCAL_IMAGE) .

build-local-amd64: require-builder ## amd64 image via emulation (java-base:local-amd64)
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64 --load $(BUILD_ARGS) -t $(NAME):local-amd64 .

smoke: ## print arch, java -version, JAVA_HOME, and uid 10001
	docker run --rm $(LOCAL_IMAGE) sh -c 'uname -m && java -version && echo JAVA_HOME=$$JAVA_HOME'
	docker run --rm --user app $(LOCAL_IMAGE) sh -c 'id && java -version'
	docker image ls $(LOCAL_IMAGE)

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
