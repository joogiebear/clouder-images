# ClouderNode Satisfactory dedicated server image.
#
# Tools only, like the Rust image: SteamCMD and the game (a download of about 3 GB) are downloaded into the
# server's data volume on first start, so the image holds no Valve or Coffee Stain binaries.
#
# Build locally:  docker build -t clouder/satisfactory:1 satisfactory
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 libstdc++6 tini \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

# The agent picks the uid (the game refuses to run as root), so nothing here may assume one.
# HOME is the data volume: saves land in /data/.config/Epic/FactoryGame/Saved/SaveGames.
ENV HOME=/data
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
