# Tools only: SteamCMD and the game are downloaded into the data volume on first start.
FROM debian:bookworm-slim AS shim
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
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
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# The agent chooses the uid, so HOME is the data volume, the only writable place.
ENV HOME=/data
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
