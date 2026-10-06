# ClouderNode Rust dedicated server image.
#
# The image holds only the tools. SteamCMD and the game itself (about 10 GB) are downloaded
# into the server's data volume on first start, and the game is updated on later starts. One
# small image therefore serves every Rust server, a game update never needs a new image, and
# the image contains no Valve binaries, so publishing it does not redistribute SteamCMD.
#
# Build locally:  docker build -t clouder/rust:1 rust
# Builds keepstdin.so, which the game needs (see keepstdin.c). The compiler stays in this stage.
FROM debian:bookworm-slim AS shim
RUN apt-get update  && apt-get install -y --no-install-recommends gcc libc6-dev  && rm -rf /var/lib/apt/lists/*
COPY keepstdin.c /src/keepstdin.c
RUN gcc -O2 -shared -fPIC -o /keepstdin.so /src/keepstdin.c -ldl

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 lib32stdc++6 libsdl2-2.0-0 libstdc++6 tini unzip \
 && rm -rf /var/lib/apt/lists/*

COPY --from=shim /keepstdin.so /usr/local/lib/keepstdin.so
COPY entrypoint.sh /entrypoint.sh
# Strip carriage returns in case the script was checked out with Windows line endings.
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# The container runs as whatever user the agent chooses (see docker.go), so nothing here
# may assume a particular uid. HOME points at the data volume, the only writable place.
ENV HOME=/data
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
