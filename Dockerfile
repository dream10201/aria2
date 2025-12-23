FROM alpine:latest AS builder
RUN apk update \
    && apk add --no-cache aria2 \
    && apk add --no-cache bash \
    && apk add --no-cache curl \
    && apk add --no-cache jq \
    && mkdir -p /libs \
    && for cmd in aria2c bash curl jq; do \
        for lib in $(ldd $(which $cmd) | grep "=> /" | awk '{print $3}'); do \
            cp "$lib" /libs/; \
        done \
    done \
    && rm -rf /var/cache/apk/*
FROM  alpine:latest
COPY --from=builder /usr/bin/aria2c /bin/bash /usr/bin/curl /usr/bin/jq /bin
COPY --from=builder /libs/. /lib/
COPY trackers_refresh.sh /trackers_refresh.sh
CMD ["aria2c","--conf-path=/etc/aria2/aria2.conf"]
