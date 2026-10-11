# Tools only: SteamCMD and the game are downloaded into the data volume on first start.
FROM debian:bookworm-slim AS rcon
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
COPY rcon.c /src/rcon.c
RUN gcc -O2 -o /rcon /src/rcon.c

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 lib32stdc++6 libstdc++6 tini \
 && rm -rf /var/lib/apt/lists/*

COPY --from=rcon /rcon /usr/local/bin/rcon
COPY console /usr/local/bin/console
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/console \
 && chmod 0755 /entrypoint.sh /usr/local/bin/console

# The agent chooses the uid, so HOME is the data volume, the only writable place.
ENV HOME=/data
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
