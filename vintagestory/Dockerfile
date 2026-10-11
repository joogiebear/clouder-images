# Tools only: the Vintage Story server is downloaded into the data volume on first start.
FROM mcr.microsoft.com/dotnet/runtime:10.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq tini \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY console /usr/local/bin/clouder-console
RUN sed -i 's/\r$//' /entrypoint.sh /usr/local/bin/clouder-console \
 && chmod 0755 /entrypoint.sh /usr/local/bin/clouder-console

# The agent chooses the uid, so HOME is the data volume, the only writable place.
ENV HOME=/data
ENV DOTNET_ROLL_FORWARD=Major
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
WORKDIR /data
VOLUME /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
