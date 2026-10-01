# bnet-launch

Launch Battle.net games through Wine from a Sunshine/Moonlight shortcut. On a cold start, `Battle.net.exe --exec=launch WoW` can open Battle.net without starting WoW. This script waits for Battle.net to become ready and sends the launch request again when needed.

WoW still uses Battle.net's normal sign-on flow, so a valid Battle.net session avoids a separate in-game login. The script does not automate the launcher UI or bypass authentication. If Battle.net asks you to sign in again, you must complete that sign-in.

## Usage

```bash
WINEPREFIX="$HOME/Games/battlenet" ./bnet-launch.sh WoW
```

The product code is optional and defaults to `WoW`; run `./bnet-launch.sh --help` for command help.

| Code | Game |
| --- | --- |
| `WoW` | World of Warcraft |
| `WoWC` | World of Warcraft Classic |
| `WoWF` | World of Warcraft: Forever beta |

[More product codes](https://steamcommunity.com/sharedfiles/filedetails/?id=1113049716) are available, and the first argument is passed to Battle.net unchanged.

## Sunshine / Moonlight

On a Linux host, add a World of Warcraft application in Sunshine. Leave **Command** empty and add this entry to **Detached Commands**, replacing both paths with absolute paths on your host:

```text
env WINEPREFIX=/home/you/Games/battlenet /path/to/bnet-launch.sh WoW
```

The wrapper exits after sending the launch request. A detached command lets the stream continue; end the stream from Moonlight when you finish playing. The wrapper does not track when WoW exits. If Sunshine runs as a Flatpak, put `flatpak-spawn --host` before `env`. See [Sunshine's application guidance](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2getting__started.html) for these command behaviors.

## How it works

The script starts `Battle.net.exe "--exec=launch <PRODUCT>"` and reads new Battle.net log entries. If the process becomes an IPC client, it waits for the request to finish. On a cold start, it waits for login and GameController initialization, then checks whether a launch marker identifies the requested product. If no matching marker appears, it sends the launch request again through IPC.

The product check looks for `InstallState (<product>): GameLaunching=1`, ignoring case. A marker for another product does not count. If Battle.net uses a different log identifier for a product code, the script will send the second request.

## Custom runners

Set `BNET_RUNNER` when another tool manages the Wine installation. The runner receives the executable path followed by Battle.net's arguments and should pass them through unchanged. For example:

```bash
#!/usr/bin/env bash
exec your-runner-command "$@"
```

```bash
BNET_RUNNER=/path/to/runner \
BNET_LOG_DIR=/path/to/Battle.net/Logs \
./bnet-launch.sh WoW
```

Set `BNET_LOG_DIR` if the runner uses a different prefix or the script cannot find its logs.

## Configuration

| Variable | Description | Default |
| --- | --- | --- |
| `WINEPREFIX` | Wine prefix | `~/.wine` |
| `WINE_BIN` | Wine executable | `wine` |
| `BNET_EXE` | Windows path to `Battle.net.exe` | `C:\Program Files (x86)\Battle.net\Battle.net.exe` |
| `BNET_EXE_UNIX` | Host path used to verify the executable | Derived from `WINEPREFIX` |
| `BNET_RUNNER` | Custom runner executable | unset |
| `BNET_LOG_DIR` | Battle.net log directory | Found in the Wine prefix |
| `BNET_LAUNCH_TIMEOUT` | Seconds to wait for readiness | `120` |
| `BNET_CLASSIFY_TIMEOUT` | Seconds to wait for IPC mode | `15` |

## Troubleshooting

- **Cannot classify IPC mode:** Check that Battle.net starts and that `BNET_LOG_DIR` points to readable logs.
- **Readiness timeout:** Check that Battle.net can log in with the selected prefix or runner. A failed primary process reports its exit status immediately. If startup is slow, try `BNET_LAUNCH_TIMEOUT=180 ./bnet-launch.sh WoW`.
- **Executable not found:** If Battle.net is installed elsewhere, set both executable paths for that invocation:

  ```bash
  BNET_EXE='C:\custom\path\Battle.net.exe' \
  BNET_EXE_UNIX='/custom/host/path/Battle.net.exe' \
  ./bnet-launch.sh WoW
  ```

## Development

Run `bash tests/launch.sh` to check the log handling with a synthetic runner. It does not start Wine or Battle.net.

## License

This project is licensed under the [MIT License](LICENSE).
