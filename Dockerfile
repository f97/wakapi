# ========================
# 🏗 Build stage
# ========================
FROM --platform=$BUILDPLATFORM golang:alpine AS build-env
WORKDIR /src

# Cài các công cụ cần thiết
RUN apk add --no-cache git wget build-base

# Tải script wait-for-it để chờ dịch vụ DB sẵn sàng
RUN wget "https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh" -O wait-for-it.sh && \
    chmod +x wait-for-it.sh

# Copy và tải dependency
COPY ./go.mod ./go.sum ./
RUN go mod download

# Copy toàn bộ source code
COPY . .

# Thiết lập biến môi trường build đa nền tảng
ARG TARGETOS
ARG TARGETARCH

# Build binary
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=0 GOEXPERIMENT=greenteagc,jsonv2 \
    go build -ldflags "-s -w" -v -o wakapi main.go

# Chuẩn bị staging area
WORKDIR /staging
RUN mkdir -p ./data ./app && \
    cp /src/wakapi app/ && \
    cp /src/config.default.yml app/config.yml && \
    sed -i 's/listen_ipv6: ::1/listen_ipv6: "-"/g' app/config.yml && \
    cp /src/wait-for-it.sh app/ && \
    cp /src/entrypoint.sh app/ && \
    chown -R 1000:1000 ./data

# ========================
# 🚀 Run stage
# ========================
FROM alpine:3
WORKDIR /app

# Tạo user không đặc quyền
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/sh -D app && \
    apk add --no-cache bash ca-certificates tzdata

# Tạo và cấp quyền ghi cho /data
RUN mkdir -p /data && \
    chown -R app:app /data && \
    chmod -R 775 /data

# Biến môi trường mặc định
ENV ENVIRONMENT=prod \
    WAKAPI_DB_TYPE=sqlite3 \
    WAKAPI_DB_USER='' \
    WAKAPI_DB_PASSWORD='' \
    WAKAPI_DB_HOST='' \
    WAKAPI_DB_NAME=/data/wakapi.db \
    WAKAPI_PASSWORD_SALT='' \
    WAKAPI_LISTEN_IPV4='0.0.0.0' \
    WAKAPI_INSECURE_COOKIES='true' \
    WAKAPI_ALLOW_SIGNUP='true'

# Copy file từ build stage
COPY --from=build-env /staging /

# Metadata chuẩn OCI
LABEL org.opencontainers.image.url="https://github.com/muety/wakapi" \
    org.opencontainers.image.documentation="https://github.com/muety/wakapi" \
    org.opencontainers.image.source="https://github.com/muety/wakapi" \
    org.opencontainers.image.title="Wakapi" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.description="A minimalist, self-hosted WakaTime-compatible backend for coding statistics"

# Chạy dưới quyền user app
USER app

# Port mặc định
EXPOSE 3000

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
