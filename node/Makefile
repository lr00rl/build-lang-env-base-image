# node-base: official Node on Alpine, plus uid 10001.
#
# Three lines Harbor / services actually use:
#   make node-build-versions   # 18-alpine, 20-alpine, 22-alpine
#                              # each: -arm64, -amd64, and a dual-arch index
#
# One version:
#   make node-build-local-arm64 NODE=22
#   make node-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1 NODE=20
#
# Or from this directory: make build-versions && make smoke-versions
SHELL := /bin/bash

NODE          ?= 20
DISTRO        ?= alpine
# 18, 20, 22 are the three alpine tags in use (Harbor 18/20, UIs on 22).
NODES         ?= 18 20 22
VERSION       ?= $(shell date +%Y.%m).1
REGISTRY      ?=
NAME          ?= node-base
IMAGE         := $(REGISTRY)/$(NAME)
LINE          := $(NODE)-$(DISTRO)
TAG           := $(LINE)-$(VERSION)
# Extra registry tag besides $(TAG). Default :18-alpine / :20-alpine.
# Harbor already has those as official mirrors. Set ALIAS_TAG= to push only
# :18-alpine-multiarch (VERSION=multiarch).
ALIAS_TAG     ?= $(LINE)
LOCAL_BUILDER ?= $(shell docker buildx ls 2>/dev/null | awk 'NR>1 && $$2=="docker" { gsub(/\*$$/, "", $$1); print $$1; exit }')
MULTI_BUILDER ?= multiarch
PLATFORMS     ?= linux/amd64,linux/arm64

BUILD_ARGS := --build-arg NODE_VERSION=$(NODE) --build-arg DISTRO=$(DISTRO) \
	--label org.opencontainers.image.version=$(TAG) \
	--label org.opencontainers.image.revision=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown) \
	--label org.opencontainers.image.created=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LOCAL_FLAGS := --provenance=false --sbom=false

.DEFAULT_GOAL := help
.PHONY: help build-local build-local-arm64 build-local-amd64 build-local-multi \
	build-versions smoke smoke-arm64 smoke-amd64 smoke-multi smoke-versions \
	builder push push-versions digest require-registry require-builder

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-18s %s\n", $$1, $$2}'

require-builder:
	@test -n "$(LOCAL_BUILDER)" || { echo "no docker-driver builder found. run: docker buildx ls"; exit 1; }

# Native arch, tagged like Harbor: node-base:20-alpine
build-local: require-builder ## native-arch image -> node-base:<N>-alpine
	docker buildx build --builder $(LOCAL_BUILDER) --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):$(LINE) .

build-local-arm64: require-builder ## arm64-only -> node-base:<N>-alpine-arm64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):$(LINE)-arm64 .

build-local-amd64: require-builder ## amd64-only -> node-base:<N>-alpine-amd64
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) -t $(NAME):$(LINE)-amd64 .

# Dual-arch index keeps the Harbor-shaped name node-base:20-alpine as well.
build-local-multi: require-builder ## dual-arch -> node-base:<N>-alpine and :<N>-alpine-multi
	docker buildx build --builder $(LOCAL_BUILDER) --platform linux/amd64,linux/arm64 --load $(LOCAL_FLAGS) $(BUILD_ARGS) \
	  -t $(NAME):$(LINE) -t $(NAME):$(LINE)-multi .

build-versions: ## 18-alpine + 20-alpine + 22-alpine (each arm64 / amd64 / multi)
	@for n in $(NODES); do \
	  $(MAKE) build-local-arm64 build-local-amd64 build-local-multi NODE=$$n DISTRO=$(DISTRO); \
	done

smoke: ## print arch, node/npm versions, and uid 10001
	docker run --rm $(NAME):$(LINE) sh -c 'uname -m && node --version && npm --version'
	docker run --rm --user app $(NAME):$(LINE) sh -c 'id && node --version'
	docker image ls $(NAME):$(LINE)

smoke-arm64: ## smoke node-base:<N>-alpine-arm64 (uname must be aarch64)
	docker run --rm --platform linux/arm64 $(NAME):$(LINE)-arm64 sh -c 'uname -m && node --version && npm --version'
	docker run --rm --platform linux/arm64 --user app $(NAME):$(LINE)-arm64 sh -c 'id && node --version'
	@docker image inspect $(NAME):$(LINE)-arm64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-amd64: ## smoke node-base:<N>-alpine-amd64 (uname must be x86_64)
	docker run --rm --platform linux/amd64 $(NAME):$(LINE)-amd64 sh -c 'uname -m && node --version && npm --version'
	docker run --rm --platform linux/amd64 --user app $(NAME):$(LINE)-amd64 sh -c 'id && node --version'
	@docker image inspect $(NAME):$(LINE)-amd64 --format 'loaded {{.Os}}/{{.Architecture}} {{.Id}}'

smoke-multi: ## show both platforms on node-base:<N>-alpine, then run each
	@docker image ls --tree $(NAME) | awk '/$(LINE)-multi|$(LINE) /,/^$$/'
	docker run --rm --platform linux/arm64 $(NAME):$(LINE) sh -c 'uname -m && node --version'
	docker run --rm --platform linux/amd64 $(NAME):$(LINE) sh -c 'uname -m && node --version'

smoke-versions: ## smoke 18, 20, and 22 alpine lines
	@for n in $(NODES); do \
	  $(MAKE) smoke-arm64 smoke-amd64 smoke-multi NODE=$$n DISTRO=$(DISTRO); \
	done

builder: ## create the multi-arch (docker-container) builder once
	docker buildx inspect $(MULTI_BUILDER) >/dev/null 2>&1 || docker buildx create --name multiarch --driver docker-container --bootstrap

require-registry:
	@test -n "$(REGISTRY)" || { echo "set REGISTRY, e.g. make push REGISTRY=ghcr.io/your-org"; exit 1; }

push: require-registry builder ## multi-arch build + push (requires REGISTRY)
	docker buildx build --builder $(MULTI_BUILDER) --platform $(PLATFORMS) $(BUILD_ARGS) \
	  --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) $(if $(ALIAS_TAG),-t $(IMAGE):$(ALIAS_TAG)) --push .
	@$(MAKE) --no-print-directory digest

# Harbor-shaped tags: $REGISTRY/node:18-alpine-multiarch (and 20, 22).
# Does not also write :18-alpine, so the existing official mirror stays.
push-versions: require-registry ## push 18/20/22 as :<N>-alpine-$(VERSION) only
	@for n in $(NODES); do \
	  $(MAKE) push NODE=$$n DISTRO=$(DISTRO) REGISTRY="$(REGISTRY)" VERSION="$(VERSION)" NAME="$(NAME)" ALIAS_TAG=; \
	done

digest: require-registry ## print tag@sha256 for service Dockerfiles
	@echo "$(IMAGE):$(TAG)@$$(crane digest $(IMAGE):$(TAG))"
