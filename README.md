# clouder-images

Container images that ClouderNode nodes run game servers in. They are public so a node can pull them without credentials.

| Folder | Image | First start downloads |
| --- | --- | --- |
| `rust/` | `ghcr.io/joogiebear/clouder-rust` | SteamCMD and Rust (about 10 GB) |
| `satisfactory/` | `ghcr.io/joogiebear/clouder-satisfactory` | SteamCMD and Satisfactory (about 3 GB) |

## How the images work

The images hold only tools: SteamCMD's dependencies and tini. SteamCMD and the game are downloaded into the `/data` volume on first start and updated on later starts, so the images contain no Valve or Coffee Stain binaries and a game update never needs a new image.

Both run as whatever uid the agent chooses, with `HOME=/data` as the only writable location. All configuration comes from environment variables set by the panel. Numeric values that are not numbers, and unsafe values for names and branches, fall back to their defaults.

## Rust

| Variable | Default | Notes |
| --- | --- | --- |
| `RCON_PASSWORD` | required | WebRCON password |
| `SERVER_PORT` | `28015` | Game port, UDP |
| `QUERY_PORT` | `28017` | Query port, UDP |
| `RCON_PORT` | `28016` | WebRCON port, TCP |
| `APP_PORT` | `28082` | Rust+ port, used only when `RUST_PLUS=true` |
| `IDENTITY` | `clouder` | Save folder name |
| `SERVER_NAME` | `Rust Server` | |
| `SERVER_DESCRIPTION` | empty | |
| `SERVER_URL` | empty | |
| `LEVEL` | `Procedural Map` | |
| `WORLD_SIZE` | `3000` | |
| `SEED` | `12345` | |
| `MAX_PLAYERS` | `50` | |
| `SAVE_INTERVAL` | `600` | Seconds |
| `RUST_PLUS` | `false` | The game aborts at startup if Rust+ cannot reach its own public address |
| `FRAMEWORK` | `vanilla` | `vanilla`, `carbon` or `oxide` |
| `CARBON_BUILD` | `production_build` | Carbon release tag |
| `OXIDE_BUILD` | `latest` | Oxide release tag |
| `UPDATE_ON_START` | `1` | Update the game and the framework on every start |
| `STEAM_BRANCH` | `public` | |

Carbon loads plugins from `server/carbon/plugins` and Oxide from `server/oxide/plugins`, both under `/data`. Oxide patches the game's own `Assembly-CSharp.dll`, so leaving Oxide validates the game files once to restore Valve's copy. The installed Oxide version is printed in the log.

`keepstdin.so` is preloaded into the game. The game's Epic Online Services library closes file descriptor 0, which makes Mono abort when Carbon writes a file or Rust+ opens a socket. The shim turns `close(0)` into a no-op.

## Satisfactory

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_PORT` | `7777` | Game port (UDP) and server API (TCP) |
| `RELIABLE_PORT` | `8888` | TCP |
| `MAX_PLAYERS` | `4` | |
| `AUTOSAVE_COUNT` | `5` | Rotating autosave files kept |
| `STEAM_BRANCH` | `public` | `public` or `experimental` |
| `DISABLE_SEASONAL_EVENTS` | `false` | |
| `UPDATE_ON_START` | `1` | Update the game on every start |
| `VALIDATE_ON_START` | `0` | Verify every game file during the update; adds minutes to each start |

Saves are written to `/data/.config/Epic/FactoryGame/Saved/SaveGames`. The community image refuses to run as any uid but 1000, so this one starts the game binary itself.

## Stopping

Rust is `exec`ed by its entrypoint, so the agent's RCON `quit`, or Docker's SIGTERM as the fallback, reaches the game directly. Satisfactory has no console. Its entrypoint turns SIGTERM into the interrupt the game saves and exits on, and a requested stop exits 0.

## Publishing

Each image has its own workflow. A change under an image folder runs shellcheck, hadolint, a build and a smoke test, and on `main` also publishes. Pull requests run everything except publishing. The run summary shows the reference with its digest (`name:tag@sha256:...`); the ClouderNode panel pins that digest, so nodes run exactly the image that was tested even if a tag is later moved.

The digest pins the image only. SteamCMD, Carbon and Oxide are downloaded when a server starts, and they follow the game on purpose, because a framework build is tied to a game build.

## Development

```
docker build -t clouder/rust:1 rust
bash test/rust.sh clouder/rust:1
```

The smoke tests replace SteamCMD and the game with stubs, so they check the entrypoints, uid handling and shutdown without downloading anything from Valve.
