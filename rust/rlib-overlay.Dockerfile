# syntax=docker/dockerfile:1.7
#
# Adds /opt/rust-cache/<gnu-triple> onto an existing rust-base (fetch +
# toolchain already in the FROM). Cook those trees on the build machine
# with `make cook-rlibs` so LLVM writes to the host disk, not Colima's
# 20 GB image store. COPY is files only, so the same blob lands on every
# TARGETPLATFORM without QEMU cargo.
ARG BASE
FROM ${BASE}
COPY x86_64-unknown-linux-gnu /opt/rust-cache/x86_64-unknown-linux-gnu
COPY aarch64-unknown-linux-gnu /opt/rust-cache/aarch64-unknown-linux-gnu
COPY .cooked /opt/rust-cache/.cooked
