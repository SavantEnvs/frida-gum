# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for frida-gum — builds the gum-graft Mayhem target and the
# upstream GLib test suite on top of the org C/C++ base image.
FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# frida-gum builds GLib and its other dependencies from vendored meson subprojects, so the
# only extra build tooling needed on top of the base is meson/ninja and setuptools (GLib's
# gio dbus codegen imports distutils, dropped from Python 3.12 stdlib). Installed at build
# time (network available); build.sh never fetches, so the offline re-run stays air-gapped.
USER root
RUN pip3 install --no-cache-dir --break-system-packages "meson>=1.3.0" ninja setuptools
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
