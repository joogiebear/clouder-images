# clouder-images

Container images that ClouderNode nodes run game servers in. They are public so a node can pull them without credentials.

| Folder | Image | First start downloads |
| --- | --- | --- |
| `rust/` | `ghcr.io/joogiebear/clouder-rust` | SteamCMD and Rust (about 10 GB) |
| `satisfactory/` | `ghcr.io/joogiebear/clouder-satisfactory` | SteamCMD and Satisfactory (about 3 GB) |
| `valheim/` | `ghcr.io/joogiebear/clouder-valheim` | SteamCMD and Valheim (about 1 GB) |
| `palworld/` | `ghcr.io/joogiebear/clouder-palworld` | SteamCMD and Palworld (about 5 GB) |
| `terraria/` | `ghcr.io/joogiebear/clouder-terraria` | The Terraria server from terraria.org (about 45 MB) |
| `projectzomboid/` | `ghcr.io/joogiebear/clouder-projectzomboid` | SteamCMD and Project Zomboid (about 7 GB) |
| `cs2/` | `ghcr.io/joogiebear/clouder-cs2` | SteamCMD and Counter-Strike 2 (about 75 GB) |
| `7dtd/` | `ghcr.io/joogiebear/clouder-7dtd` | SteamCMD and 7 Days to Die (about 18 GB) |
| `factorio/` | `ghcr.io/joogiebear/clouder-factorio` | The Factorio headless server from factorio.com (about 0.2 GB) |
| `ark/` | `ghcr.io/joogiebear/clouder-ark` | SteamCMD and ARK: Survival Evolved (about 15 GB) |
| `bedrock/` | `ghcr.io/joogiebear/clouder-bedrock` | The Bedrock dedicated server from minecraft.net (about 0.1 GB) |
| `dst/` | `ghcr.io/joogiebear/clouder-dst` | SteamCMD and Don't Starve Together (about 4 GB) |
| `gmod/` | `ghcr.io/joogiebear/clouder-gmod` | SteamCMD, Garry's Mod and the Counter-Strike: Source content (about 9 GB) |
| `vintagestory/` | `ghcr.io/joogiebear/clouder-vintagestory` | The Vintage Story server from vintagestory.at (about 0.1 GB) |

## How the images work

The images hold only tools: SteamCMD's dependencies and tini. SteamCMD and the game are downloaded into the `/data` volume on first start and updated on later starts, so the images contain no Valve or Coffee Stain binaries and a game update never needs a new image.

All run as whatever uid the agent chooses, with `HOME=/data` as the only writable location. All configuration comes from environment variables set by the panel. Numeric values that are not numbers, and unsafe values for names and branches, fall back to their defaults.

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

## Valheim

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_PORT` | `2456` | Game port, UDP. The query port is always this number plus one |
| `SERVER_NAME` | `Valheim Server` | |
| `WORLD_NAME` | `Dedicated` | A world is generated the first time a name is used |
| `SERVER_PASSWORD` | empty | Empty, or at least 5 characters and not part of the server name |
| `PUBLIC` | `false` | Show in the server list |
| `CROSSPLAY` | `false` | |
| `PRESET` | `normal` | `normal`, `casual`, `easy`, `hard`, `hardcore`, `immersive` or `hammer` |
| `SAVE_INTERVAL` | `1800` | Seconds |
| `BACKUPS` | `4` | Automatic backups kept |
| `UPDATE_ON_START` | `1` | Update the game on every start |

Worlds and the admin, ban and permitted lists are written to `/data/saves`. The game saves and exits on SIGINT.

## Palworld

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_PORT` | `8211` | Game port, UDP |
| `QUERY_PORT` | `27015` | Steam query port, UDP |
| `SERVER_NAME` | `Palworld Server` | |
| `SERVER_DESCRIPTION` | empty | |
| `SERVER_PASSWORD` | empty | |
| `ADMIN_PASSWORD` | empty | Empty turns admin commands off |
| `MAX_PLAYERS` | `16` | |
| `PVP` | `false` | |
| `DEATH_PENALTY` | `All` | `None`, `Item`, `ItemAndEquipment` or `All` |
| `EXP_RATE` | `1` | `0.5`, `1`, `2`, `3`, `5` or `10` |
| `PUBLIC_LOBBY` | `false` | Show in the community server list |
| `UPDATE_ON_START` | `1` | Update the game on every start |
| `VALIDATE_ON_START` | `0` | Verify every game file during the update; adds minutes to each start |

The options above are written into `PalWorldSettings.ini` on every start; every other option in that file is left as it is. The entrypoint prints `Palworld is ready` once the game port is bound, because the game itself logs nothing that says so. The game saves and exits on SIGTERM.

## Terraria

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_PORT` | `7777` | TCP |
| `WORLD_NAME` | `World` | A world is generated the first time a name is used |
| `WORLD_SIZE` | `2` | `1` small, `2` medium or `3` large; new worlds only |
| `DIFFICULTY` | `0` | `0` classic, `1` expert, `2` master or `3` journey; new worlds only |
| `SEED` | empty | New worlds only |
| `MAX_PLAYERS` | `8` | |
| `SERVER_PASSWORD` | empty | |
| `MOTD` | `Welcome!` | |
| `TERRARIA_VERSION` | `1458` | The version without dots: 1458 is 1.4.5.8 |

The server is downloaded from terraria.org into `/data/server/<version>` and `/data/serverconfig.txt` is written from the variables on every start. Worlds are in `/data/worlds`. The game reads its console from a pipe; `clouder-console <line>` writes a line to it, and a stop sends `exit`, which saves the world.

## Project Zomboid

| Variable | Default | Notes |
| --- | --- | --- |
| `SERVER_PORT` | `16261` | UDP |
| `UDP_PORT` | `16262` | Direct connection port, UDP |
| `STEAM_PORT1` | `8766` | UDP |
| `STEAM_PORT2` | `8767` | UDP |
| `SERVER_NAME` | `servertest` | Names the save and its settings file |
| `PUBLIC_NAME` | `Project Zomboid Server` | Name in the server browser |
| `PUBLIC` | `false` | Show in the server browser |
| `SERVER_PASSWORD` | empty | |
| `ADMIN_PASSWORD` | empty | Empty makes one up, prints it in the log and keeps it in `/data/.admin-password` |
| `MAX_PLAYERS` | `16` | |
| `PVP` | `true` | |
| `XMX` | `4g` | Java heap, set by the panel from the server's memory |
| `STEAM_BRANCH` | `public` | `public`, `unstable` or `legacy41` |
| `UPDATE_ON_START` | `1` | Update the game on every start |

The variables above are written into `/data/Zomboid/Server/<SERVER_NAME>.ini` on every start; every other setting in the file is left as it is. The game reads its console from a pipe; `clouder-console <line>` writes a line to it, and a stop sends `quit`, which saves the world.

## Minecraft Bedrock, Don't Starve Together, Garry's Mod and Vintage Story

| Variable | Minecraft Bedrock | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP; the IPv6 port is this number plus one | `19132` |
| `SERVER_NAME`, `LEVEL_NAME`, `LEVEL_SEED` | Name in the server list, world folder name and seed (seed applies to new worlds) | `Bedrock Server`, `Bedrock level`, empty |
| `GAMEMODE` | `survival`, `creative` or `adventure` | `survival` |
| `DIFFICULTY` | `peaceful`, `easy`, `normal` or `hard` | `easy` |
| `ALLOW_CHEATS` | | `false` |
| `MAX_PLAYERS`, `VIEW_DISTANCE` | | `10`, `32` |
| `ONLINE_MODE` | Require Xbox Live sign-in | `true` |
| `ALLOW_LIST` | Only players in `allowlist.json` may join | `false` |
| `BEDROCK_VERSION` | `latest` or a version such as `1.21.80.3` | `latest` |

The server zip is downloaded from minecraft.net into `/data/server` and replaced whenever the wanted version differs from the installed one; worlds, `server.properties`, `allowlist.json` and `permissions.json` are kept. The variables above are written into `server.properties` on every start and every other line is left as it is. The server reads its console from a pipe; `clouder-console <line>` writes a line to it, and a stop sends `stop`, which saves the world.

| Variable | Don't Starve Together | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP | `10999` |
| `CLUSTER_TOKEN` | Server token from accounts.klei.com; required, the entrypoint refuses to start without it | none |
| `SERVER_NAME`, `SERVER_DESCRIPTION`, `SERVER_PASSWORD` | | `Dont Starve Together Server`, empty, empty |
| `GAME_MODE` | `survival`, `endless` or `wilderness` | `survival` |
| `MAX_PLAYERS` | | `6` |
| `PVP` | | `false` |
| `PAUSE_WHEN_EMPTY` | | `true` |
| `ENABLE_CAVES` | Run a second shard with the caves inside the same container | `false` |
| `WORKSHOP_MODS` | Comma separated workshop ids, downloaded and enabled on both shards | empty |
| `CLUSTER_KEY` | Secret the two shards share; the panel generates it | `clouder` |
| `UPDATE_ON_START`, `VALIDATE_ON_START` | | `1`, `0` |

The cluster lives in `/data/DoNotStarveTogether/Cluster` and `cluster.ini`, both `server.ini` files and the token are written on every start. The master shard reads its console from a pipe; `clouder-console <line>` writes a Lua line to it (`c_save()`, `c_announce("hi")`), and a stop sends `c_shutdown(true)` to every shard, which saves the world. The caves shard listens on 127.0.0.1 only; players join through the master shard.

| Variable | Garry's Mod | Default |
| --- | --- | --- |
| `RCON_PASSWORD` | required | none |
| `SERVER_PORT` | Game port, UDP; RCON listens on the same number over TCP inside the container | `27015` |
| `SERVER_NAME` | | `Garry's Mod Server` |
| `GAMEMODE` | A gamemode folder name: `sandbox`, `terrortown`, or one from the workshop | `sandbox` |
| `MAP` | | `gm_construct` |
| `MAX_PLAYERS`, `TICKRATE` | | `16`, `66` |
| `SERVER_PASSWORD` | Join password, empty for none | empty |
| `STEAM_TOKEN` | Game server login token for app 4000; without one the server ranks lower in the browser | empty |
| `WORKSHOP_COLLECTION`, `WORKSHOP_AUTHKEY` | Workshop collection id and a Steam Web API key; both are needed to load it | empty |
| `MOUNT_CSS` | Download Counter-Strike: Source and mount it, which many maps need | `1` |
| `STEAM_BRANCH`, `UPDATE_ON_START`, `VALIDATE_ON_START` | | `public`, `1`, `0` |

The console is Source RCON through the `console` script, like Counter-Strike 2. The engine only writes its console output to the log when asked, so the entrypoint starts it with `-condebug` and relays `garrysmod/console.log` to the container's log, and it prints `Garry's Mod is accepting connections` once RCON answers.

| Variable | Vintage Story | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, TCP and UDP | `42420` |
| `SERVER_NAME`, `SERVER_DESCRIPTION`, `SERVER_PASSWORD` | Letters, numbers, spaces and `_ . ! # ( ) -` only | `Vintage Story Server`, empty, empty |
| `MAX_PLAYERS` | | `16` |
| `WORLD_SEED` | Applies to new worlds | empty |
| `ADVERTISE` | List the server publicly | `false` |
| `WHITELIST` | Only whitelisted players may join | `false` |
| `ALLOW_PVP`, `PASS_TIME_WHEN_EMPTY` | | `true`, `false` |
| `VS_VERSION` | `latest` (the current stable release) or a version such as `1.22.7` | `latest` |

The server is downloaded from vintagestory.at into `/data/server` and replaced when the wanted version differs; the world, mods and `serverconfig.json` live in `/data/data`. The variables above are applied to `serverconfig.json` on every start with the server's own `--setconfig`, which leaves every other setting alone. Mods go in `/data/data/Mods`. The server runs on the .NET 10 runtime image, with roll-forward enabled so older releases that target .NET 8 also start. The server reads its console from a pipe; `clouder-console <line>` writes a line to it (commands start with `/`), and a stop sends `/stop`, which saves the world.

## Counter-Strike 2, 7 Days to Die, Factorio and ARK

These four share a console. Each image has a `console` script that types one line into the game's own console from inside the container (Source RCON for Counter-Strike 2, Factorio and ARK, telnet for 7 Days to Die) and prints the answer to the container's log. The agent runs it with `docker exec <container> console "<line>"`, so the console ports are never published. The panel generates `RCON_PASSWORD`, and the entrypoint refuses to start without it.

Each game starts in the background and the entrypoint traps SIGTERM: it saves through the console, asks the game to quit, and exits 0, so both the agent's stop command and a plain `docker stop` end with a saved world.

| Variable | Counter-Strike 2 | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP; the RCON console listens on the same number over TCP, inside the container | `27015` |
| `SERVER_NAME` | | `Counter-Strike 2 Server` |
| `GAME_MODE` | `casual`, `competitive`, `wingman`, `armsrace`, `demolition` or `deathmatch` | `competitive` |
| `MAP` | Starting map | `de_dust2` |
| `MAX_PLAYERS` | | `10` |
| `SERVER_PASSWORD` | Join password, empty for none | empty |
| `STEAM_TOKEN` | Game server login token (app 730); without one the server is not listed publicly | empty |
| `UPDATE_ON_START` | Update the game on every start | `1` |
| `VALIDATE_ON_START` | Verify every game file during the update | `0` |

Extra settings go in `server/game/csgo/cfg/server.cfg`, which runs on every map load.

| Variable | 7 Days to Die | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP and TCP | `26900` |
| `SERVER_NAME`, `SERVER_DESCRIPTION`, `SERVER_PASSWORD` | | `7 Days to Die Server`, empty, empty |
| `MAX_PLAYERS` | | `8` |
| `GAME_WORLD` | `RWG` or `Navezgane` | `RWG` |
| `WORLD_SEED`, `WORLD_SIZE`, `SAVE_NAME` | Seed and size (`6144`, `8192` or `10240`) of a generated `RWG` world, and the save name | `clouder`, `6144`, `Clouder` |
| `VISIBILITY` | `listed`, `friends` or `unlisted` | `listed` |
| `EAC_ENABLED` | Easy Anti-Cheat | `true` |
| `STEAM_BRANCH` | | `public` |
| `UPDATE_ON_START`, `VALIDATE_ON_START` | As above | `1`, `0` |

The entrypoint copies the game's `serverconfig.xml` to `/data/serverconfig.xml` once and rewrites only the properties above on each start, so everything else in the file can be edited by hand. Saves are written to `/data/userdata`. Telnet listens on 8081 inside the container. Difficulty and the other gameplay rules are set in the sandbox settings of the game itself (`SandboxCode`) and can be edited in `/data/serverconfig.xml`.

| Variable | Factorio | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP | `34197` |
| `FACTORIO_VERSION` | `stable`, `latest` or a version such as `2.0.77` | `stable` |
| `SERVER_NAME`, `SERVER_DESCRIPTION`, `GAME_PASSWORD` | | `Factorio Server`, empty, empty |
| `MAX_PLAYERS` | `0` for no limit | `0` |
| `VISIBILITY` | `lan` or `public`; public needs the next two | `lan` |
| `FACTORIO_USERNAME`, `FACTORIO_TOKEN` | factorio.com account for the public server list | empty |
| `AUTOSAVE_INTERVAL` | Minutes | `10` |
| `AUTO_PAUSE` | Pause when nobody is online | `true` |
| `ALLOW_COMMANDS` | `admins-only`, `true` or `false` | `admins-only` |
| `UPDATE_ON_START` | Check for a newer build of the chosen version on every start | `1` |

The server is downloaded from factorio.com into `/data/server`; saves, mods and config live beside it in `/data/saves`, `/data/mods` and `/data/config`. A new map is created on first start. `server-settings.json` is the game's own example file with the variables above written into it on each start.

| Variable | ARK: Survival Evolved | Default |
| --- | --- | --- |
| `SERVER_PORT` | Game port, UDP; the game also uses the next port up for raw sockets | `7777` |
| `QUERY_PORT` | Steam query port, UDP | `27015` |
| `SERVER_NAME` | | `ARK Server` |
| `MAP` | `TheIsland`, `TheCenter`, `Ragnarok`, `ScorchedEarth_P` and so on | `TheIsland` |
| `MAX_PLAYERS` | | `20` |
| `SERVER_PASSWORD` | Join password, empty for none | empty |
| `ADMIN_PASSWORD` | In-game admin password; empty falls back to `RCON_PASSWORD` | empty |
| `STEAM_BRANCH`, `UPDATE_ON_START`, `VALIDATE_ON_START` | As above | `public`, `1`, `0` |

Settings beyond these go in `server/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini` and `Game.ini`. ARK: Survival Ascended is Windows-only and needs Proton, so it is not included.

## Stopping

Rust is `exec`ed by its entrypoint, so the agent's RCON `quit`, or Docker's SIGTERM as the fallback, reaches the game directly. Satisfactory has no console. Its entrypoint turns SIGTERM into the interrupt the game saves and exits on, and a requested stop exits 0. Valheim and Palworld work the same way and have no console either. Terraria, Project Zomboid, Minecraft Bedrock, Don't Starve Together and Vintage Story read their console from a pipe, so their entrypoints turn SIGTERM into the game's own save-and-exit command. Garry's Mod works like Counter-Strike 2.

## Publishing

Each image has its own workflow. A change under an image folder runs shellcheck, hadolint, a build and a smoke test, and on `main` also publishes. Pull requests run everything except publishing. The run summary shows the reference with its digest (`name:tag@sha256:...`); the ClouderNode panel pins that digest, so nodes run exactly the image that was tested even if a tag is later moved.

The digest pins the image only. SteamCMD, Carbon and Oxide are downloaded when a server starts, and they follow the game on purpose, because a framework build is tied to a game build.

## Development

```
docker build -t clouder/rust:1 rust
bash test/rust.sh clouder/rust:1
```

The smoke tests replace SteamCMD and the game with stubs, so they check the entrypoints, uid handling and shutdown without downloading anything from Valve.
