# Simmer ☕

**Close the lid. Keep working.**

Simmer is a tiny menu-bar cup that keeps your Mac running, even with the lid
closed, so downloads, builds and remote sessions don't get cut off. Turn it off
and the Mac sleeps normally again.

> The app and its commands are still called **Awake** (`Awake.app`, `awake`,
> `asleep`). Simmer is the project name.

## What it does

- **Works with the lid closed.** Wi-Fi stays on and your task keeps going.
- **One click.** Click the cup; it turns orange and steams while it's on.
- **Timers.** Keep awake for 30 minutes, an hour, or until a command finishes.
- **Turns itself off.** It stops on low battery or if the Mac runs hot with the
  lid closed, and tells you with a notification.
- **Three ways to toggle.** Menu bar, Control Center and Terminal always agree.

## Requirements

- macOS 26 or later
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Install

Before you build, make two small edits so it works on your Mac:

1. In `sudoers.d/awake`, replace `mohdkhan` with your macOS username.
2. In `project.yml`, replace `DEVELOPMENT_TEAM` with your Apple team ID.

Then:

```sh
git clone https://github.com/mdanassaif/Simmer.git
cd Simmer
./install.sh
```

This puts `awake` and `asleep` in `~/.local/bin`, builds `Awake.app` into
`~/Applications`, and opens it.

Last, run the one command the installer prints (it starts with `sudo visudo`).
It lets the app switch lid sleep without asking for your password each time.

## Use it

### Menu bar

Click the cup:

| Menu item | What it does |
| --- | --- |
| Keep Awake | On until you turn it off |
| Keep Awake For › 30 Minutes… | On for a set time, then off by itself |
| Turn Off | Back to normal sleep |

The top line of the menu shows how much time is left.

### Control Center

Add the tile once: Control Center › Edit Controls › Awake.

### Terminal

```sh
awake               # on until you run asleep
awake 45m           # on for 45 minutes (also 90s, 2h, 1h30m)
awake -- make build # on while the command runs
asleep              # off
awake status        # what's going on
```

## Safety

So a forgotten session can't drain or overheat the Mac, it stops on its own:

- when your timer or command finishes,
- on battery at 10% or less (20% or less with the lid closed),
- if the Mac runs hot with the lid closed.

Don't put a closed, awake Mac in a bag.

The limits can be changed with environment variables; see `awake --help`.

## Troubleshooting

- **"Awake needs a one-time setup"**: run the `sudo visudo …` command it shows
  (the alert has a Copy button).
- **`awake: command not found`**: add `~/.local/bin` to your PATH:
  `print 'path=(~/.local/bin $path)' >> ~/.zshrc`
- **Lid sleep seems stuck off**: run `asleep`, then `awake status` should say
  `lid sleep   enabled`.
- **No cup in the menu bar**: open `~/Applications/Awake.app`.

## Uninstall

```sh
asleep
rm ~/.local/bin/awake ~/.local/bin/asleep
rm -rf ~/Applications/Awake.app ~/.cache/awake
sudo rm /etc/sudoers.d/awake
```
