# Language runtime base images.
#   make python-build-local python-smoke
#   make java-build-local java-smoke
#   make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1
#   make java-push    REGISTRY=ghcr.io/your-org VERSION=2026.09.1
SHELL := /bin/bash

# Forwarded into python/ and java/ on *-push / *-digest.
REGISTRY ?=
VERSION  ?=

.DEFAULT_GOAL := help
.PHONY: help python-% java-%

help: ## list language-prefixed targets
	@echo "python (see python/README.md):"
	@$(MAKE) -s -C python help | sed 's/^/  python-/'
	@echo
	@echo "java (see java/README.md):"
	@$(MAKE) -s -C java help | sed 's/^/  java-/'
	@echo
	@echo "Example: make python-build-local   make java-smoke"
	@echo "Push:    make python-push REGISTRY=ghcr.io/your-org VERSION=2026.09.1"

python-%:
	@$(MAKE) -C python $(@:python-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")

java-%:
	@$(MAKE) -C java $(@:java-%=%) REGISTRY="$(REGISTRY)" $(if $(VERSION),VERSION="$(VERSION)")
