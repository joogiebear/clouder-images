# clouder-images

Container images that ClouderNode nodes run game servers in. They are public so a customer's
node can pull them without credentials.

| Folder | Image | What it is |
| --- | --- | --- |
| `rust/` | `ghcr.io/joogiebear/clouder-rust` | Tools only: SteamCMD dependencies and tini. The game (about 10 GB) is downloaded into the server's data volume on first start, so the image contains no Valve binaries. |
| `satisfactory/` | `ghcr.io/joogiebear/clouder-satisfactory` | Tools only, like Rust: SteamCMD dependencies and tini. The game (about 3 GB download) is installed into the data volume on first start. Runs as any non-root user, which the community image does not. |

Pushing a change to an image folder on `main` builds and publishes it. The run's summary shows
the reference with its digest (`name:tag@sha256:...`); the ClouderNode panel pins that digest, so
nodes run exactly the image that was tested even if a tag is later moved.

Build locally: `docker build -t clouder/rust:1 rust`
