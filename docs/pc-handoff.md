# Handoff: making the tweaks work on a regular (PC) Omarchy install

Written on 2026-09-30 by Claude on the Mac (M1 Pro, Omarchy-Mac 4.0.3rc4,
aarch64) for a Claude session on the HP laptop (regular Omarchy, x86_64). The
conversation can't be resumed across machines; this file is everything the
next session needs. Delete it once the PC works.

## The report

On the HP, after running the installer from the setup window: window borders
and keybinds worked; the dock, the "configuration menu", the Settings app and
most other things did not. The display driver (`smidriver`) installed, but
there was no way to configure monitors (that lives in the Settings app's
Displays pane and in Setup > Witcher's Tweaks > Configure).

## What was found (from the Mac, by reading upstream's source)

Nothing below was run on a PC. It comes from diffing the installed
`/usr/share/omarchy` on the Mac against `basecamp/omarchy` v4.0.4 and the
`quattro` branch.

1. **One failing step aborted the whole install.** `install.sh` runs under
   `set -e`. The `agentchat` tweak installed `qmltermwidget` with
   `omarchy pkg add`, which calls `sudo`; the setup window has no terminal, so
   it failed and everything after `agentchat` in the `tweaks` list was skipped
   (notifytimeout, overview, titlebars, borderresize, dock, suspend, ...), the
   Setup > Witcher's Tweaks menu entry was never written and the shell was
   never restarted. Tweaks before it (borders, keybinds) were in.

2. **Omarchy 4.0.3 final and later scope the plugin API.** Third-party plugins
   get `PluginShellApi` / `PluginBarApi` facades instead of the real `shell`
   and `bar` (`shell/services/Plugin*Api.qml`, `shell/Ui/PluginBarApi.qml`,
   `pluginShellFor()` in `shell/shell.qml`). Under the facade:
   - `shell.shellConfig` does not exist: dock, idle-suspend and notify-timeout
     read no settings (dock: defaults, nothing pinned, so no Settings icon).
   - `shell.mutateShellConfig` returns false for non-bar plugins: the dock
     could not save pinned apps.
   - `shell.appLibrary` is null unless the plugin is a `menu`: the dock falls
     back to `DesktopEntries` (that fallback already existed).
   - `firstPartyServiceFor("omarchy.notifications")` returns null: the bell
     and notify-timeout had no notification service.
   - `shell.hide(<own id>)`, `shell.updateEntryInline(<own id>, settings)`,
     `bar.foreground/urgent/fontFamily`, injected `settings` still work.
   The Mac is on 4.0.3rc4, from before this change, which is why it all works
   there.

Things checked and found the same on both: `OMARCHY_PATH=/usr/share/omarchy`,
the shell launch command (`quickshell -n -p $OMARCHY_PATH/shell`), the menu
extension file, the hooks folders, every `omarchy-*` command the repo calls,
and the Settings app and wizard QML loading against upstream's `Commons`/`Ui`.

## What was changed (uncommitted at the time of writing, then pushed on a branch)

- `install.sh`
  - `run_tweak`: each tweak's steps run in a subshell; a failure is recorded
    in `failed_tweaks`, the rest carry on, and the menu, Hyprland reload and
    shell restart still happen. Exit status is 1 with a `failed   <names>`
    line. Flags set by steps (`reload_hypr`, `restart_shell`,
    `reboot_reasons`) come back through a temp file.
  - `pkg_add` / `pkg_aur_add`: with `SUDO=pkexec` (setup window, Settings
    app) they run `pacman` / `yay --sudo pkexec` directly instead of the
    `omarchy pkg` commands that need a terminal for sudo.
  - Hyprland config errors no longer exit before the shell restart.
  - `notifytimeout` has a new file: `witcher.notify-timeout/bin/expire-popups`.
- `witcher.dock/Dock.qml`, `witcher.idle-suspend/Service.qml`,
  `witcher.notify-timeout/Service.qml`: `shellConfig` property that uses
  `shell.shellConfig` when it exists, else a `FileView` on
  `~/.config/omarchy/shell.json`.
- `witcher.dock/Dock.qml`: `writePinned` uses `shell.updateEntryInline`.
- `witcher.notify-timeout`: when the shell is the facade
  (`!("shellConfig" in shell)`), a `Process` runs `bin/expire-popups`, which
  watches `~/.local/state/omarchy/notifications/*.json` (one file per toast on
  screen) and calls `omarchy-shell -q notifications dismiss <summary>`.
- `witcher.notifications`: without the service, `notification-store --live`
  also lists the on-screen toasts (`"onScreen": true`); dismissing uses the
  `notifications dismiss` / `dismissAll` IPC; the refresh timer is 5 s.
- `README.md`: compatibility note.

Tested on the Mac only: `bash -n`, a standalone test of `run_tweak`,
`qmllint` on the edited QML, `--status`. The facade code paths have never
run.

## What to do on the HP

Follow the user's global rules (no git commands unless told, never assume,
ask when unclear). Ask before anything that restarts the shell or reloads
Hyprland if the user has other work running.

1. Record the facts first:
   ```bash
   uname -m; omarchy version; pacman -Q omarchy quickshell hyprland
   echo "$OMARCHY_PATH"; ls /usr/share/omarchy/shell/services | grep -i plugin
   pgrep -af quickshell
   ./install.sh --status
   ```
   `PluginShellApi.qml` present means the facade is in play (cause 2). If the
   version is older than 4.0.3 final, only cause 1 applies.
2. Look at what the first attempt left behind: `~/.config/omarchy/shell.json`
   (`plugins` and `bar.layout`), `~/.config/omarchy/plugins/`,
   `~/.config/witchers-tweaks/tweaks.conf`,
   `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
3. Re-run the installer for the tweaks the user wants, from a terminal first
   (`./install.sh --tui` or `./install.sh <names>`), and read every `failed`
   line. Then try the setup window (`./install.sh --gui`) to check the
   `pkexec` path, ideally with `qmltermwidget` not yet installed.
4. Read the shell's log for plugin errors:
   `quickshell log -p /usr/share/omarchy/shell | grep -iE "witcher|warn|error"`.
5. Verify each of these and fix what doesn't hold:
   - Dock: appears, shows pinned apps (Settings first), honours settings
     changed in the Settings app's Dock pane, drag-to-keep persists in
     `shell.json`, App drawer lists and launches apps, SUPER+M minimizes.
   - Bell: lists on-screen and past notifications; dismissing one and
     Dismiss all work (`notify-send test body` to try).
   - notifytimeout: a toast leaves after the set seconds;
     `pgrep -af expire-popups` shows the helper.
   - suspend: `minutes` from `shell.json` is used (log line on idle).
   - overview, border picker: open and close (`shell.hide` on own id).
   - titlebars: hyprbars builds for this Hyprland; buttons appear; the bar
     widget shows while a window is maximized.
   - agentchat: terminal appears in the widget; the color scheme link under
     `/usr/lib/qt6/qml/QMLTermWidget/color-schemes/` exists.
   - Settings app: opens from the launcher and from Setup > Witcher's Tweaks
     > Configure; every pane loads; Displays applies and saves monitors.
   - smidriver: x64 binaries; monitors show up in Displays.
   - `fans` and `touchbar` must not be offered (`./install.sh --list`).

## Known weak spots to look at

- The notification fallback dismisses by summary substring: toasts sharing a
  summary go together, one with an empty summary can't be dismissed, and it
  counts as "dismissed" rather than "expired".
- `FileView` + `watchChanges` on `shell.json`: confirm settings changes show
  up live (the installer and Settings app replace the file with `mv`).
- Third-party services are created with no QML parent on 4.0.3+
  (`comp.createObject(null)`); the dock and titlebars services open their own
  windows, so check they do.
- `witcher.agents` is a clone of `omarchy.agents` (`omarchy.clonedFrom`);
  upstream's agents plugin may have moved on since it was copied.
- `yay --sudo pkexec` for `evdi-dkms` is untried; it may prompt several times.
- `upstream quattro` adds `ShellIpc`/`IpcRegistry` (a socket in front of
  `qs ipc`). Plain `IpcHandler` targets (`witcher.dock`, `witcher.agents`)
  should still be reached through the `qs ipc` fallback; confirm with
  `omarchy-shell witcher.dock minimize active`.
- Both machines must keep working: every change needs the old path
  (4.0.3rc4, real `shell`) and the facade path. Omarchy-Mac will get the
  facade when it catches up with upstream.
