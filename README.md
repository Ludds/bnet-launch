# bnet-launch

Small wrapper around Battle.net's existing `--exec` launch command for Linux/Wine.

This repository exists for the cold-start case, mainly so a Battle.net game can be exposed as normal applications in Sunshine/Moonlight without automating the launcher UI or bypassing the Battle.net authentication.

## Usage

Make it executable:

```bash
chmod +x bnet-launch.sh
```

Launch any Battle.net game via:

```bash
WINEPREFIX="$HOME/Games/battlenet" ./bnet-launch.sh {product-code}
```

Show help:

```bash
./bnet-launch.sh --help
```

## Product codes

The first argument is passed to Battle.net as the product code.

```text
WoW   World of Warcraft
WoWC  World of Warcraft Classic
WoWF  World of Warcraft: Forever beta
```

A larger list of Battle.net product codes is available here:

https://steamcommunity.com/sharedfiles/filedetails/?id=1113049716

## What the script checks

The script launches Battle.net with:

```text
Battle.net.exe "--exec=launch <PRODUCT>"
```

and watches the Battle.net logs to determine whether that process became an IPC client or the main Battle.net process.

If it sees:

```text
IPC ShMem mode=client
```

Battle.net was already running. The launch request has been forwarded to the existing instance and there is nothing else to do.

If it sees:

```text
IPC ShMem mode=server
```

this is a cold start. The script waits for Battle.net to report:

```text
Logged into Battle.net successfully.
GameController initialization complete
```

It also checks for:

```text
GameLaunching=1
```

in case the original request already started the game.

If the game has not started by the time Battle.net is ready, the script sends the `--exec` request again. The second invocation then connects to the running Battle.net instance as an IPC client.

Only log output written after the current launch attempt is considered.

## Sunshine / Moonlight

This is the reason I wrote the script.

Instead of exposing Battle.net itself in Sunshine, I can expose WoW as an application and use this as the launch command:

```bash
WINEPREFIX="$HOME/Games/battlenet" \
/path/to/bnet-launch.sh WoW
```

Battle.net still handles authentication, updates, and launching the game. Sunshine just gets a command it can treat like any other application.

The same approach can also be used from Steam shortcuts, desktop entries, or shell scripts.

## Custom runners

Plain Wine works directly.

If your Battle.net installation is managed by something else, set `BNET_RUNNER` to a wrapper or command that can launch `Battle.net.exe`.

The runner is called with the executable followed by the Battle.net arguments:

```text
$BNET_RUNNER "$BNET_EXE" "--exec=launch WoW"
```

For example:

```bash
#!/usr/bin/env bash
exec your-runner-command "$@"
```

Then:

```bash
BNET_RUNNER=/path/to/runner \
BNET_LOG_DIR=/path/to/Battle.net/Logs \
./bnet-launch.sh WoW
```

For custom runners, `BNET_LOG_DIR` may need to be set explicitly so the script can find Battle.net's logs.

## Configuration

| Variable | Description | Default |
| --- | --- | --- |
| `WINEPREFIX` | Wine prefix | `~/.wine` |
| `WINE_BIN` | Wine executable | `wine` |
| `BNET_EXE` | Windows path to `Battle.net.exe` | `C:\Program Files (x86)\Battle.net\Battle.net.exe` |
| `BNET_EXE_UNIX` | Host path used to verify the Battle.net executable | Derived from `WINEPREFIX` |
| `BNET_RUNNER` | Optional custom runner | unset |
| `BNET_LOG_DIR` | Battle.net log directory | Auto-detected from the Wine prefix |
| `BNET_LAUNCH_TIMEOUT` | Time to wait for Battle.net to become ready | `120` seconds |
| `BNET_CLASSIFY_TIMEOUT` | Time to wait for IPC client/server detection | `15` seconds |

Example:

```bash
BNET_LAUNCH_TIMEOUT=180 \
WINEPREFIX="$HOME/Games/battlenet" \
./bnet-launch.sh WoW
```

## Troubleshooting

### Could not determine whether Battle.net became an IPC client or server

The script probably cannot find or read the Battle.net logs.

If you're using a custom runner, set the log directory manually:

```bash
BNET_LOG_DIR=/path/to/Battle.net/Logs
```

### Battle.net starts but the script times out

Battle.net may need longer to log in or initialize `GameController`.

Try:

```bash
BNET_LAUNCH_TIMEOUT=180 ./bnet-launch.sh WoW
```

Also make sure Battle.net can start and log in normally in the same prefix or runner environment.

### Battle.net executable not found

With plain Wine, the default is:

```text
C:\Program Files (x86)\Battle.net\Battle.net.exe
```

Override it if your installation is somewhere else:

```bash
BNET_EXE='C:\custom\path\Battle.net.exe'
BNET_EXE_UNIX='/custom/host/path/Battle.net.exe'
```