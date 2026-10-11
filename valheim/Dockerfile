# Tools only: SteamCMD and the game are downloaded into the data volume on first start.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 libatomic1 libpulse0 libstdc++6 tini \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# The agent chooses the uid, so HOME is the data volume, the only writable place.
ENV HOME=/data
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
