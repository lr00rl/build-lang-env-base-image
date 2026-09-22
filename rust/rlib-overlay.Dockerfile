# syntax=docker/dockerfile:1.7
#
# Adds an amd64-host cargo target dir onto an existing rust-base.
# `release/` is the host build scripts and proc-macros. Each GNU triple
# dir is the rlibs for that --target. Cook with CARGO_TARGET_DIR=/cache/target
# on an amd64 host (Rosetta is enough; QEMU is not) so the fingerprints
# match Jenkins. COPY is files only, so the same blob lands on every
# TARGETPLATFORM.
ARG BASE
FROM ${BASE}
COPY release /opt/rust-cache/release
COPY x86_64-unknown-linux-gnu /opt/rust-cache/x86_64-unknown-linux-gnu
COPY aarch64-unknown-linux-gnu /opt/rust-cache/aarch64-unknown-linux-gnu
COPY .cooked /opt/rust-cache/.cooked
