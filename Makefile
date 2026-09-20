# Language runtime base images.
#   make python-build-local python-smoke
#   make java-build-local java-smoke
#   make node-build-local node-smoke
#   make rust-build-local rust-smoke
#   make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#   make java-push    REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#   make node-push    REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#   make rust-push    REGISTRY=ghcr.io/your-org VERSION=2026.09.1
SHELL := /bin/bash

# Forwarded into python/, java/, node/, and rust/ on *-push / *-digest.
REGISTRY ?=
VERSION  ?=

.DEFAULT_GOAL := help
.PHONY: help python-% java-% node-% rust-%

help: ## list language-prefixed targets
	@echo "python (see python/README.md):"
	@$(MAKE) -s -C python help | sed 's/^/  python-/'
	@echo
	@echo "java (see java/README.md):"
	@$(MAKE) -s -C java help | sed 's/^/  java-/'
	@echo
	@echo "node (see node/README.md):"
	@$(MAKE) -s -C node help | sed 's/^/  node-/'
	@echo
	@echo "rust (see rust/README.md):"
	@$(MAKE) -s -C rust help | sed 's/^/  rust-/'
	@echo
	@echo "Example: make python-build-local   make java-smoke   make rust-smoke"
	@echo "Push:    make node-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1"

python-%:
	@$(MAKE) -C python $(@:python-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")

java-%:
	@$(MAKE) -C java $(@:java-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")

node-%:
	@$(MAKE) -C node $(@:node-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")

rust-%:
	@$(MAKE) -C rust $(@:rust-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")
