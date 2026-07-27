# syntax=docker/dockerfile:1
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app
COPY . .

RUN flutter pub get

RUN dart pub global activate dart_frog_cli
ENV PATH="$PATH:/root/.pub-cache/bin"

WORKDIR /app/apps/server
RUN mkdir -p public && dart_frog build

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

FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/apps/server/build/server ./server
COPY --from=build /app/apps/server/build/public ./public
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
