FROM golang:alpine AS build
RUN apk add --no-cache git
WORKDIR /app
RUN git clone https://github.com/pocketbase/pocketbase.git
WORKDIR /app/pocketbase
RUN go build -o /bin/pocketbase ./examples/base

FROM alpine:latest
COPY --from=build /bin/pocketbase /usr/local/bin/pocketbase
WORKDIR /pb_data
EXPOSE 8090
ENTRYPOINT ["/usr/local/bin/pocketbase"]
CMD ["serve", "--http=0.0.0.0:8090"]
