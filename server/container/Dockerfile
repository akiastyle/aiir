FROM alpine:3.20 AS build
RUN apk add --no-cache build-base musl-dev
WORKDIR /src
COPY ai /src/ai
RUN cd /src/ai/toolchain-native && ./build-static.sh

FROM scratch
WORKDIR /app
COPY --from=build /src/ai/toolchain-native/aiird-static /app/aiird
COPY --from=build /src/ai/core /app/core
ENV AI_CORE_DIR=/app/core
ENV AI_RUNTIME_HOST=0.0.0.0
ENV AI_RUNTIME_PORT=7788
ENV AI_DB_EXEC_MODE=dry-run
EXPOSE 7788
ENTRYPOINT ["/app/aiird","serve"]
