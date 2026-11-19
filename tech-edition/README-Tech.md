# ImpactLED Cloud+ Tech Edition

The Impact Cloud+ Desktop Player, packaged for techs to install on their **own PC** to test and experiment. It is the same player that runs on production signs. Only the installer differs.

| | Tech Edition | Production sign install |
|---|---|---|
| Installer | One `Setup.exe`, double-click | `full-install.bat` from an Admin Command Prompt |
| Admin rights | **Not needed** | Required |
| Starts automatically | **Never** | At every logon (watchdog task) |
| Restarts itself | **Never** | Watchdog restarts it on crash/hang |
| Auto-update | **None** (run a newer installer) | Updater task, 5 min after boot |
| Closing it | **Closes it for good** | Watchdog brings it back |
| Install folder | `%LOCALAPPDATA%\Programs\ImpactLED Cloud+ Tech Edition` | `C:\ImpactLED\CloudPlayer` |

## Install

1. Download `ImpactLED-CloudPlus-Tech-Setup-<version>.exe` from the **Releases** page of the Cloud-Desktop-Edition repo. Tech builds are marked **Pre-release**.
2. Double-click it.
   - Windows SmartScreen may say *"Windows protected your PC"* because the installer is not signed. Click **More info**, then **Run anyway**.
3. Optionally enter your **test** Terminal ID, Terminal Secret and Cloud+ server URL.
   - Leave them blank to skip. You can enter them later in the player (press **F12**).
   - Use credentials made for testing, **not** the ones from a live sign. Give each PC its own Terminal ID.
4. Tick **Launch now**, or start it from the Start menu (**ImpactLED Cloud+ Tech Edition**).
   - There is an optional desktop shortcut on the installer's Additional shortcuts page.

## Using it

| Key | Action |
|---|---|
| `ESC` or `Q` | Quit (the player closes completely) |
| `F11` | Toggle fullscreen |
| `F12` | Settings: Cloud+ server, Terminal ID, secret, resolution |
| `O` | Open a local `.vsn` file |
| `Space` | Pause / resume |
| `I` | Toggle the info overlay |
| `P` | Push a screenshot to Cloud+ |

- **It always starts windowed** (the shortcuts pass `-w`). Press `F11` to go fullscreen for that session.
- A console window opens beside the player and shows the live log. This is useful when testing. Closing the console also closes the player.
- **Close the player before launching it again.** Two copies on one PC share one identity in Cloud+ and will confuse the CMS.
- Each install generates its own device serial (`CLCAPC######`) on first run. It is stored in `player_config.json`.

## Windows Firewall prompt

On first launch with Cloud+ enabled, Windows may ask to allow the player on the network. It listens on port 8989 for the local API. You can click **Cancel**: connecting to Cloud+ is outbound-only and works regardless.

## Update

Download a newer Tech Edition installer and run it. It closes a running player, replaces the program files and **keeps your `player_config.json`**.

## Uninstall

Windows **Settings > Apps > Installed apps > ImpactLED Cloud+ Tech Edition > Uninstall**. This also removes the downloaded programs, screenshots and the config file.

## Where things are

Open the install folder from **Start menu > ImpactLED Cloud+ Tech Edition > Open install folder**.

- `player_config.json`: this PC's settings (credentials included, so don't share it)
- `downloads\`: programs synced from Cloud+
- `screenshot_*.png`: screenshots

## Something wrong?

- **Black or idle screen:** no Cloud+ credentials yet. Press `F12` and enter the Server URL, Terminal ID and Secret.
- **Won't launch after an interrupted install:** run the installer again.
- **Never starts by itself, and that is intended.** If you do want it at logon, add a shortcut to `shell:startup` yourself. Nothing in the Tech Edition does this for you.
