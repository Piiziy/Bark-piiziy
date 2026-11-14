# Image for Google Cloud Run (`gcloud run deploy --source server`).
# Build context: the server/ directory. See cloudrun/README.ko.md.
# The self-hosted docker-compose stack uses selfhost/Dockerfile instead.
FROM golang:1.26-alpine AS builder
ARG BUILD_VERSION=cloudrun
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath \
      -ldflags "-X 'main.version=${BUILD_VERSION}' -X 'main.buildDate=$(date '+%F %T')' -w -s" \
      -o /out/bark-server .

FROM alpine:3.22
ENV TZ=Asia/Seoul
RUN apk add --no-cache ca-certificates tzdata \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone
COPY --from=builder /out/bark-server /usr/local/bin/bark-server
# Group -> default icon table baked into the image (edit, then redeploy).
COPY cloudrun/group-icons.json /etc/bark/group-icons.json
ENV BARK_SERVER_SERVERLESS=true \
    BARK_GROUP_ICONS_FILE=/etc/bark/group-icons.json
EXPOSE 8080
CMD ["bark-server"]
