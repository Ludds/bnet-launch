# Battle.net game launcher for Linux

Launch a Battle.net game directly from Linux while keeping Battle.net's normal SSO flow.

Primarily intended for launchers and game-streaming setups such as Sunshine/Moonlight,
where the game should be launchable directly without automating the Battle.net UI.

Requires Bash and a working Battle.net installation under Wine or a compatible runner.

## Product codes

`bnet-launch` accepts a Battle.net product code as its first argument.

Currently documented codes include:

```text
WoW   World of Warcraft
WoWC  World of Warcraft Classic
WoWF  World of Warcraft: Forever beta
```

`WoWF` is currently associated with the Forever beta and may change when Forever releases.

For other games and current product codes, see the community-maintained list:

https://steamcommunity.com/sharedfiles/filedetails/?id=1113049716

## Plain Wine

```bash
chmod +x bnet-launch.sh
WINEPREFIX=/path/to/battlenet-prefix ./bnet-launch.sh WoW
```

`WoW` is the default, so this also works:

```bash
WINEPREFIX=/path/to/battlenet-prefix ./bnet-launch.sh
```

Current WoW Forever beta:

```bash
WINEPREFIX=/path/to/battlenet-prefix ./bnet-launch.sh WoWF
```

## How it works

The script first sends:

```text
Battle.net.exe "--exec=launch <PRODUCT>"
```

If Battle.net is already running, the request is forwarded to the existing instance through Battle.net's IPC mechanism and the game launches normally.

On a cold start, the first process can become the primary Battle.net instance instead. The script waits for Battle.net to log in and initialize `GameController`, then sends the launch command again.

## Custom runners (Lutris, Bottles, Proton, UMU, etc.)

Set `BNET_RUNNER` to a runner command or executable wrapper that can run `Battle.net.exe` inside the correct environment.

The runner is called as:

```text
$BNET_RUNNER "$BNET_EXE" "--exec=launch WoW"
```

Example wrapper:

```bash
#!/usr/bin/env bash
exec your-runner-command "$@"
```

Then:

```bash
BNET_RUNNER=/path/to/your-wrapper \
BNET_LOG_DIR=/path/to/Battle.net/Logs \
./bnet-launch.sh WoW
```

If the runner uses a different Wine prefix than `WINEPREFIX`, set `BNET_LOG_DIR` explicitly so the script can find Battle.net's logs.

## Configuration

```text
WINEPREFIX             Wine prefix, defaults to ~/.wine
WINE_BIN               Wine executable, defaults to wine
BNET_EXE               Windows path to Battle.net.exe
BNET_EXE_UNIX          Host path used to verify Battle.net is installed
BNET_RUNNER            Optional runner command or executable wrapper
BNET_LOG_DIR           Optional explicit Battle.net log directory
BNET_LAUNCH_TIMEOUT    Readiness timeout, defaults to 120 seconds
BNET_CLASSIFY_TIMEOUT  IPC client/server detection timeout, defaults to 15 seconds
```

The readiness check currently watches for:

```text
Logged into Battle.net successfully.
GameController initialization complete
```

and distinguishes cold and warm launches using:

```text
IPC ShMem mode=server
IPC ShMem mode=client
```
