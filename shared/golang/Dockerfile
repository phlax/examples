FROM debian:bookworm-slim@sha256:b1211f6d19afd012477bd34fdcabb6b663d680e0f4b0537da6e6b0fd057a3ec3 AS os-base
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | tee /etc/apt/apt.conf.d/keep-cache


FROM golang:1.24.5-bookworm@sha256:69adc37c19ac6ef724b561b0dc675b27d8c719dfe848db7dd1092a7c9ac24bc6 AS golang-base


FROM golang-base AS golang-control-plane-builder
ARG GO_RESOURCE=resource.go
RUN git clone https://github.com/envoyproxy/go-control-plane && cd go-control-plane && git checkout b4adc3bb5fe5288bff01cd452dad418ef98c676e
ADD "$GO_RESOURCE" /go/go-control-plane/internal/example/resource.go
RUN cd go-control-plane && make bin/example
WORKDIR /go/go-control-plane


FROM os-base AS golang-control-plane
ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get -qq update \
    && apt-get -qq install --no-install-recommends -y netcat-traditional
COPY --from=golang-control-plane-builder /go/go-control-plane/bin/example /usr/local/bin/example


FROM golang-base AS golang-base-builder
ARG GO_APP=.
ARG GO_APP_NAME=grpc-service
RUN echo "COPY $GO_APP -> ${GO_APP_NAME} ..."
COPY "$GO_APP" /app


FROM golang-base-builder AS golang-grpc-auth-builder
RUN make -C "/app/${GO_APP_NAME}"


FROM os-base AS golang-grpc-auth
COPY --from=golang-grpc-auth-builder /app/grpc-service/server /app/server
CMD ["/app/server", "-users", "/etc/users.json"]


FROM golang-base AS golang-grpc-server-builder
WORKDIR /build
# Resolve and build Go dependencies as Docker cache
COPY go.mod /build/go.mod
COPY go.sum /build/go.sum
ENV GO111MODULE=on
RUN go mod download
COPY service.go /build/main.go
COPY kv/ /build/kv
# Build for linux
ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0
RUN go build -o server


FROM os-base AS golang-grpc-server
WORKDIR /root/
# Copy the linux amd64 binary
COPY --from=golang-grpc-server-builder /build/server /bin/
ENTRYPOINT /bin/server


FROM golang-base AS golang-lrs-builder
COPY ./server /go/src/github.com/envoyproxy/envoy/example/load-reporting-service/server
COPY *.go /go/src/github.com/envoyproxy/envoy/example/load-reporting-service/
COPY go.sum /go/src/github.com/envoyproxy/envoy/example/load-reporting-service
COPY go.mod /go/src/github.com/envoyproxy/envoy/example/load-reporting-service
WORKDIR /go/src/github.com/envoyproxy/envoy/example/load-reporting-service
RUN go mod download \
    && go install /go/src/github.com/envoyproxy/envoy/example/load-reporting-service


FROM os-base AS golang-lrs
COPY --from=golang-lrs-builder /go/bin/load-reporting-service /usr/local/bin/load-reporting-service
CMD ["load-reporting-service"]
