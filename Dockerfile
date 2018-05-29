FROM alpine:edge AS builder

WORKDIR /tmp/pg_test
RUN apk add --update --no-cache crystal shards g++ gc-dev libc-dev libevent-dev libxml2-dev llvm llvm-dev llvm-libs llvm-static make openssl openssl-dev pcre-dev readline-dev yaml-dev zlib-dev libpq
COPY pg_test.cr .
COPY shard.yml .
RUN shards build --production && strip -S bin/pg_test

FROM alpine:edge
RUN apk add --update libgcc openssl libevent gc pcre dumb-init libpq
WORKDIR /bin
COPY --from=builder /tmp/pg_test/bin/pg_test .
