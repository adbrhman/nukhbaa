# syntax=docker/dockerfile:1
# Pinned inputs (audit C/1): a tag can be re-pushed, so one commit could
# build a different image on another day. Each FROM keeps its tag for
# reading, but Docker pulls the @sha256 digest. To move to a new version,
# change the tag, then copy the new digest and dart_frog_cli version from
# the Build Verification log:
#   gh run view <id> --log | grep -E 'FROM .*@sha256:|Activated dart_frog_cli'
FROM ghcr.io/cirruslabs/flutter:3.44.0@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8 AS build

WORKDIR /app
COPY . .

# The sports publisher draws its pictures with resvg (script 208,
# approved 2026-11-04): MPL-2.0, one binary, pinned by its checksum.
RUN curl -fsSL -o /tmp/resvg.tar.gz \
      https://github.com/linebender/resvg/releases/download/v0.45.1/resvg-linux-x86_64.tar.gz && \
    echo "3c1d52850a78bc4ed0e9d05605b53ad21bb5313184f14bf72515d29cb98cda10  /tmp/resvg.tar.gz" \
      | sha256sum -c - && \
    mkdir -p /opt/resvg && tar -xzf /tmp/resvg.tar.gz -C /opt/resvg && \
    /opt/resvg/resvg --version

# Resolve the whole pub workspace once from the root.
RUN flutter pub get

RUN dart pub global activate dart_frog_cli 1.2.14
ENV PATH="$PATH:/root/.pub-cache/bin"

WORKDIR /app/apps/server
RUN mkdir -p public && dart_frog build

# dart_frog build copies apps/server/pubspec.yaml verbatim into build/, so it
# still carries resolution: workspace while sitting OUTSIDE the workspace
# root, and its path deps no longer resolve. Detach it and pin the internal
# packages to absolute paths before resolving.
WORKDIR /app/apps/server/build
RUN sed -i '/^resolution:[[:space:]]*workspace[[:space:]]*$/d' pubspec.yaml && \
    printf '%s\n' \
      'dependency_overrides:' \
      '  shared:' \
      '    path: /app/packages/shared' \
      '  domain:' \
      '    path: /app/packages/domain' \
      '  contracts:' \
      '    path: /app/packages/contracts' \
      '  application:' \
      '    path: /app/packages/application' \
      '  infrastructure:' \
      '    path: /app/packages/infrastructure' \
      > pubspec_overrides.yaml && \
    dart pub get && \
    dart compile exe bin/server.dart -o server

# RUNTIME BASE MUST MATCH THE BUILD BASE'S glibc.
# ghcr.io/cirruslabs/flutter:3.44.0 -> cirruslabs/android-sdk:36
# -> cirruslabs/android-sdk:tools -> ubuntu:24.04  (glibc 2.39).
# The previous runtime was debian:bookworm-slim (glibc 2.36): the image built
# fine but dart compile exe output dies at startup with
# "version `GLIBC_2.38' not found". Dart does not support cross-glibc runs.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Do not run the API as root.
RUN useradd --system --uid 10001 --create-home --shell /usr/sbin/nologin nukhba
WORKDIR /app
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/server ./server
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/public ./public
# The publisher's renderer and the one font its pictures use.
COPY --from=build --chown=nukhba:nukhba /opt/resvg/resvg ./bin/resvg
COPY --from=build --chown=nukhba:nukhba /app/apps/mobile/assets/fonts ./fonts
USER nukhba

ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
