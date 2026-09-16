FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3 ca-certificates zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG ASAR_VERSION=v1.91
RUN git clone --depth 1 --branch ${ASAR_VERSION} https://github.com/RPGHacker/asar.git /tmp/asar \
    && cmake -S /tmp/asar/src -B /tmp/asar/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/asar/build -j "$(nproc)" \
    && find /tmp/asar/build -type f -name asar -perm -u+x -exec cp {} /usr/local/bin/asar \; \
    && asar --version \
    && rm -rf /tmp/asar

# Headless libretro core, so ROM changes can be verified visually without a GUI.
# The commit is pinned because the watchpoint patch is applied against it.
ARG SNES9X_REF=890b5d445538fe790aa3add3d5702c80f551e0ae
COPY snes9x-watchpoints.patch /tmp/snes9x-watchpoints.patch
RUN git clone https://github.com/libretro/snes9x.git /tmp/snes9x \
    && git -C /tmp/snes9x checkout --quiet ${SNES9X_REF} \
    && git -C /tmp/snes9x apply --verbose /tmp/snes9x-watchpoints.patch \
    && make -C /tmp/snes9x/libretro -j "$(nproc)" \
    && cp /tmp/snes9x/libretro/snes9x_libretro.so /usr/local/lib/ \
    && rm -rf /tmp/snes9x /tmp/snes9x-watchpoints.patch

WORKDIR /work
