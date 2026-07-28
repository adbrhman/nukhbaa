# syntax=docker/dockerfile:1
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app
COPY . .

# Resolve the whole pub workspace once from the root.
RUN flutter pub get

RUN dart pub global activate dart_frog_cli
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
FROM ubuntu:24.04
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Do not run the API as root.
RUN useradd --system --uid 10001 --create-home --shell /usr/sbin/nologin nukhba
WORKDIR /app
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/server ./server
COPY --from=build --chown=nukhba:nukhba /app/apps/server/build/public ./public
USER nukhba

ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
