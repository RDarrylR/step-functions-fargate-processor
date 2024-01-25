ARG BASE_IMAGE=rust:1.75.0-slim-bullseye
ARG APP_NAME=fargate_rust_worker
FROM $BASE_IMAGE as builder
RUN mkdir /app
WORKDIR /app
COPY . .
RUN cargo build --release

FROM $BASE_IMAGE
COPY --from=builder /app/target/release/fargate_rust_worker /
CMD ["/fargate_rust_worker"]