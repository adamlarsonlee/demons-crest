FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG ASAR_VERSION=v1.91
RUN git clone --depth 1 --branch ${ASAR_VERSION} https://github.com/RPGHacker/asar.git /tmp/asar \
    && cmake -S /tmp/asar/src -B /tmp/asar/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/asar/build -j "$(nproc)" \
    && find /tmp/asar/build -type f -name asar -perm -u+x -exec cp {} /usr/local/bin/asar \; \
    && asar --version \
    && rm -rf /tmp/asar

WORKDIR /work
