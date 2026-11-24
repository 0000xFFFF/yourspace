# syntax=docker/dockerfile:1
# One Cargo workspace, two binaries:
#   web    = HTTP/WebSocket server (server-side HTML rendering)
#   worker = RabbitMQ consumer (moderation, descriptions, embeddings, thumbnails/transcoding)
# Build a specific one with:  --target web   or   --target worker

FROM lukemathwalker/cargo-chef:latest-rust-1-bookworm AS chef
WORKDIR /build

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /build/recipe.json recipe.json
# Dependency layer: cached until Cargo.toml / Cargo.lock change
RUN cargo chef cook --release --recipe-path recipe.json
COPY . .
# sqlx compile-time query checking without a live DB (run `cargo sqlx prepare` and commit .sqlx/)
ENV SQLX_OFFLINE=true
RUN cargo build --release --bin web --bin worker

# ───────────── runtime base ─────────────
FROM debian:bookworm-slim AS runtime-base
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home app \
 && mkdir -p /data/media && chown app:app /data/media
WORKDIR /app

# ───────────── web ─────────────
FROM runtime-base AS web
COPY --from=builder /build/target/release/web /app/web
COPY static /app/static
USER app
ENV BIND_ADDR=0.0.0.0:8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
CMD ["/app/web"]

# ───────────── worker (needs ffmpeg for video frames / thumbnails) ─────────────
FROM runtime-base AS worker
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/worker /app/worker
USER app
CMD ["/app/worker"]
