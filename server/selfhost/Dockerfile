# Build context: the server/ directory (see docker-compose.yml)
FROM golang:1.26-alpine AS builder
ARG BUILD_VERSION=selfhost
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath \
      -ldflags "-X 'main.version=${BUILD_VERSION}' -X 'main.buildDate=$(date '+%F %T')' -w -s" \
      -o /out/bark-server .

FROM alpine:3.22
ARG TIMEZONE=Asia/Seoul
ENV TZ=${TIMEZONE}
RUN apk add --no-cache ca-certificates tzdata wget \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone
COPY --from=builder /out/bark-server /usr/local/bin/bark-server
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["bark-server"]
