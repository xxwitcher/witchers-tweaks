#!/usr/bin/env bash
# Witcher's Tweaks: optional tweaks for Omarchy, each one added, removed or
# configured on its own.
#
#   ./install.sh                     pick tweaks category by category
#   ./install.sh --add [tweak...]    add tweaks (asks which, from those not installed)
#   ./install.sh --remove [tweak...] remove tweaks (asks which, then confirms)
#   ./install.sh --configure [name]  change settings (monitors, borders, corners, suspend, notifications, dock)
#   ./install.sh --status            which tweaks are installed
#   ./install.sh --list              list the tweaks
#   ./install.sh --all               add every tweak this machine can use
#   ./install.sh --uninstall         remove every tweak, the menu entry and the loader
#   ./install.sh --monitors          the interactive monitor setup
#   ./install.sh tweak...            add these tweaks
#
# Hyprland tweaks live in ~/.config/hypr/witchers-tweaks.lua, which one
# marked block at the end of ~/.config/hypr/hyprland.lua loads; each runs only
# while its name is in ~/.config/witchers-tweaks/tweaks.conf. Your own
# input.lua, bindings.lua and looknfeel.lua are never replaced.
#
# Other files under home/ are symlinked into $HOME; an existing file is moved
# aside to <file>.bak.<timestamp> first. Files under system/ are copied as root
# (root daemons shouldn't read from $HOME), keeping the original as .bak.
# Bar settings are edited in place in ~/.config/omarchy/shell.json.
#
# Removing a tweak undoes its steps in reverse: a linked file goes back to the
# backup it replaced (or nothing), settings leave shell.json, and system
# changes are reverted. Anything that isn't ours is left alone.
#
# Every run also adds Setup > Witcher's Tweaks to the Omarchy menu, with Add,
# Remove and Configure entries that open this script in a terminal.
#
# Set SUDO=pkexec when running without a terminal for the password prompt.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stamp="$(date +%s)"
SUDO="${SUDO:-sudo}"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

plugins="home/.config/omarchy/plugins"

# name | category | description | items
# Items: home/<path> is symlinked, system/etc/<app> is copied to /etc/<app>
# (offered only when <app> is installed), hypr:<tweak> switches a tweak in
# witchers-tweaks.lua on, and @<step> is one of the steps below (each has an
# apply, a remove and a check).
tweaks=(
  "gaps|Look|No gaps between windows|hypr:no-gaps"
  "border|Look|Spinning gradient border on windows, popups and notifications, in colors you pick|$plugins/witcher.border-colors/Picker.qml $plugins/witcher.border-colors/manifest.json $plugins/witcher.border-colors/bin/border-colors hypr:gradient-border @border-shell @border-picker @border-spin"
  "wsfade|Look|Workspaces slide in with a fade instead of switching instantly|hypr:workspace-fade"
  "columns|Look|Scrolling layout: one column per screen instead of two|hypr:wide-columns"
  "rounding|Look|Window corner rounding on a % slider (the same scale as the dock's)|hypr:window-rounding @window-rounding"
  "swapkeys|Input|Swap left Ctrl and left Super (the right-hand keys stay)|hypr:swap-ctrl-super"
  "swipe|Input|macOS-like 3-finger swipe between workspaces|hypr:workspace-swipe"
  "bindbrowser|Keybindings|SUPER+B opens the browser (instead of SUPER+SHIFT+B)|hypr:bind-browser"
  "bindagent|Keybindings|SUPER+A opens your default agent (instead of SUPER+SHIFT+A)|hypr:bind-agent"
  "bindclose|Keybindings|CTRL+Q closes the window|hypr:bind-close"
  "autohide|Top bar|Hide the bar until the cursor touches the top edge|home/.local/share/witchers-tweaks/autohide-bar hypr:autohide-bar @autohide"
  "clock|Top bar|Clock in the middle of the bar|@clock-center"
  "battery|Top bar|Battery percentage next to the battery icon|@battery-percent"
  "bell|Top bar|Bell that opens recent notifications, each dismissable, with Dismiss all|$plugins/witcher.notifications/Panel.qml $plugins/witcher.notifications/manifest.json $plugins/witcher.notifications/bin/notification-store @notify-panel"
  "agentchat|Top bar|Agent widget with your default agent's real terminal inside it|$plugins/witcher.agents/Panel.qml $plugins/witcher.agents/Main.qml $plugins/witcher.agents/Agent.qml $plugins/witcher.agents/manifest.json $plugins/witcher.agents/README.md $plugins/witcher.agents/bin/terminal-colors $plugins/witcher.agents/assets/claude.svg $plugins/witcher.agents/assets/codex.svg $plugins/witcher.agents/assets/codex-light.svg $plugins/witcher.agents/assets/fireworks.svg @agent-terminal @agent-bar"
  "notifytimeout|Notifications|Every notification leaves the screen after a few seconds (5 by default), critical ones too|$plugins/witcher.notify-timeout/Service.qml $plugins/witcher.notify-timeout/manifest.json @notify-timeout"
  "overview|Windows|Mission Control-style overview of workspaces and windows (3-finger swipe up)|$plugins/witcher.overview/Overview.qml $plugins/witcher.overview/manifest.json $plugins/witcher.overview/bin/focus-window @overview hypr:overview-gesture"
  "dock|Windows|macOS-style dock: Apps view, kept, running and recent apps, drag to arrange, Downloads, Trash, SUPER+M minimizes|$plugins/witcher.dock/Dock.qml $plugins/witcher.dock/manifest.json $plugins/witcher.dock/bin/dock $plugins/witcher.dock/AppsPanel.qml @dock hypr:dock-minimize"
  "suspend|Power|No screensaver; suspend after a chosen idle time (1-60 min)|$plugins/witcher.idle-suspend/Service.qml $plugins/witcher.idle-suspend/manifest.json @idle-suspend"
  "smidriver|Hardware|Silicon Motion SM77x USB display adapter driver (evdi-dkms based, with a crash fix)|@smi-driver"
  "touchbar|Hardware|Touch Bar layout and screenshot key (MacBooks with tiny-dfr)|system/etc/tiny-dfr"
)

categories=("Look" "Input" "Keybindings" "Top bar" "Notifications" "Windows" "Power" "Hardware")

# Settings --configure offers: name | description | function | tweak. With a
# tweak it shows only while that tweak is installed; without one, always.
configurable=(
  "monitors|Resolution, scale, rotation and position of each screen|configure_monitors|"
  "borders|Colors of the window, popup and notification borders (color picker)|configure_borders|border"
  "corners|How round window corners are (slider)|configure_window_rounding|rounding"
  "suspend|How long idle before suspending|configure_idle_suspend|suspend"
  "notifications|How long notifications stay on screen|configure_notify_timeout|notifytimeout"
  "dock|Size, magnification, position, hiding, transparency, border and more, one at a time|configure_dock|dock"
)

field() { cut -d'|' -f"$2" <<<"$1"; }

tweak_line() {
  local t
  for t in "${tweaks[@]}"; do
    [[ $(field "$t" 1) == "$1" ]] && { echo "$t"; return 0; }
  done
  return 1
}

# True when a Silicon Motion USB device is plugged in (used to start the
# driver right away after installing it).
smi_adapter_present() {
  grep -qsx 090c /sys/bus/usb/devices/*/idVendor
}

has_battery() {
  grep -qsx Battery /sys/class/power_supply/*/type
}

available() {
  local item
  command -v omarchy >/dev/null || return 1
  for item in $(field "$1" 4); do
    case "$item" in
      system/etc/*)
        local app="${item#system/etc/}"
        command -v "$app" >/dev/null || [[ -d "/usr/share/$app" ]] || return 1
        ;;
      hypr:*) [[ -f $hyprland_config ]] || return 1 ;;
      @battery-percent) has_battery || return 1 ;;
      @smi-driver) command -v pacman >/dev/null || return 1 ;;
    esac
  done
}

# ---------------------------------------------------------------- home files

link_home() {
  local rel="${1#home/}"
  local src="$repo/home/$rel" dest="$HOME/$rel"

  if [[ "$(readlink -f "$dest" 2>/dev/null)" == "$src" ]]; then
    echo "ok       ~/$rel"
    return
  fi

  mkdir -p "$(dirname "$dest")"
  if [[ -L $dest && $(readlink "$dest") == */home/"$rel" ]]; then
    # A link into another checkout of these files (an older or moved copy):
    # nothing of the user's to keep.
    rm "$dest"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    mv "$dest" "$dest.bak.$stamp"
    echo "backup   ~/$rel -> ~/$rel.bak.$stamp"
  fi
  ln -s "$src" "$dest"
  echo "linked   ~/$rel"
  [[ $rel == .config/omarchy/plugins/* ]] && restart_shell=true
  return 0
}

home_linked() {
  local rel="${1#home/}"
  [[ -L "$HOME/$rel" && "$(readlink -f "$HOME/$rel")" == "$repo/home/$rel" ]]
}

# The newest <file>.bak.<stamp> that isn't itself a link into a checkout of
# these files, i.e. what the file was before we last took it.
newest_backup() {
  local dest="$1" rel="$2" best="" best_stamp=0 candidate suffix
  for candidate in "$dest".bak.*; do
    [[ -e $candidate || -L $candidate ]] || continue
    suffix="${candidate##*.bak.}"
    [[ $suffix =~ ^[0-9]+$ ]] || continue
    [[ -L $candidate && $(readlink "$candidate") == */home/"$rel" ]] && continue
    if (( suffix > best_stamp )); then best="$candidate"; best_stamp=$suffix; fi
  done
  [[ -n $best ]] && echo "$best"
}

# Takes the link out and puts back what it replaced (the newest backup), else
# leaves nothing. Anything that isn't our link is left alone.
unlink_home() {
  local rel="${1#home/}"
  local dest="$HOME/$rel"

  if ! home_linked "$1"; then
    echo "ok       ~/$rel (not linked)"
    return 0
  fi
  rm "$dest"

  local backup
  if backup=$(newest_backup "$dest" "$rel"); then
    mv "$backup" "$dest"
    echo "restored ~/$rel from ~/${backup#"$HOME"/}"
  else
    echo "removed  ~/$rel"
  fi

  # Drop folders of ours once they're empty.
  local dir
  dir=$(dirname "$dest")
  while [[ $dir == "$HOME/.config/omarchy/plugins/"* || $dir == "$HOME/.local/share/witchers-tweaks"* ]] && rmdir "$dir" 2>/dev/null; do
    dir=$(dirname "$dir")
  done
  [[ $rel == .config/omarchy/plugins/* ]] && restart_shell=true
  return 0
}

# ---------------------------------------------------------------- hyprland

# The tweaks in witchers-tweaks.lua each run only while their name is in
# tweaks.conf. The file is loaded by a marked block at the end of the user's
# hyprland.lua, added with the first tweak and removed with the last.
hyprland_config="$HOME/.config/hypr/hyprland.lua"
state_dir="$HOME/.config/witchers-tweaks"
tweaks_conf="$state_dir/tweaks.conf"
loader_begin="-- >>> witchers-tweaks (managed by the Witcher's Tweaks install.sh)"
loader_end="-- <<< witchers-tweaks"

hypr_enabled() {
  grep -qsx "$1" "$tweaks_conf"
}

loader_installed() {
  grep -qsxF -e "$loader_begin" "$hyprland_config" && home_linked home/.config/hypr/witchers-tweaks.lua
}

ensure_loader() {
  loader_installed && return 0
  link_home home/.config/hypr/witchers-tweaks.lua
  if ! grep -qsxF -e "$loader_begin" "$hyprland_config"; then
    printf '\n%s\nrequire("hypr.witchers-tweaks")\n%s\n' "$loader_begin" "$loader_end" >>"$hyprland_config"
    echo "set      ~/.config/hypr/hyprland.lua loads witchers-tweaks.lua"
  fi
  reload_hypr=true
}

remove_loader() {
  if grep -qsxF -e "$loader_begin" "$hyprland_config"; then
    local tmp="$hyprland_config.tmp.$stamp"
    awk -v begin="$loader_begin" -v end="$loader_end" '
      $0 == begin { skip = 1; next }
      skip && $0 == end { skip = 0; next }
      !skip { print }' "$hyprland_config" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
    mv "$tmp" "$hyprland_config"
    echo "removed  the witchers-tweaks block from ~/.config/hypr/hyprland.lua"
    reload_hypr=true
  fi
  unlink_home home/.config/hypr/witchers-tweaks.lua
}

enable_hypr() {
  local name="$1"
  ensure_loader
  if hypr_enabled "$name"; then
    echo "ok       $name"
  else
    mkdir -p "$state_dir"
    echo "$name" >>"$tweaks_conf"
    echo "set      $name"
    reload_hypr=true
  fi
}

disable_hypr() {
  local name="$1"
  if hypr_enabled "$name"; then
    grep -vx "$name" "$tweaks_conf" >"$tweaks_conf.tmp.$stamp" || true
    mv "$tweaks_conf.tmp.$stamp" "$tweaks_conf"
    echo "unset    $name"
    reload_hypr=true
  else
    echo "ok       $name (not set)"
  fi
}

# With no Hyprland tweaks left, the loader and the list go too.
tidy_loader() {
  if [[ -f $tweaks_conf ]] && grep -q '[^[:space:]]' "$tweaks_conf"; then
    return 0
  fi
  if loader_installed || [[ -f $tweaks_conf ]]; then
    remove_loader
    rm -f "$tweaks_conf"
  fi
  rmdir "$state_dir" 2>/dev/null || true
}

# ---------------------------------------------------------------- system files

system_files() {
  find "$repo/$1" -type f -print0
}

system_installed() {
  local src dest
  while IFS= read -r -d '' src; do
    dest="/${src#"$repo"/system/}"
    cmp -s "$src" "$dest" || return 1
  done < <(system_files "$1")
}

copy_system() {
  local app="${1#system/etc/}"

  # Collect changed files so each app needs a single privileged call.
  local pending=() src dest
  while IFS= read -r -d '' src; do
    dest="/${src#"$repo"/system/}"
    if cmp -s "$src" "$dest"; then
      echo "ok       $dest"
    else
      pending+=("$src" "$dest")
    fi
  done < <(system_files "$1")
  (( ${#pending[@]} )) || return 0

  local service=""
  systemctl cat "$app.service" >/dev/null 2>&1 && service="$app.service"

  # A file that was there before the first install is kept as .bak so removal
  # can put it back. Later updates don't back up our own earlier copy.
  $SUDO bash -c '
    stamp="$1" service="$2"; shift 2
    while (( $# )); do
      if [[ -e $2 ]] && ! compgen -G "$2.bak.*" >/dev/null; then cp -p "$2" "$2.bak.$stamp"; fi
      install -D -m 644 "$1" "$2"
      shift 2
    done
    [[ -z "$service" ]] || systemctl restart "$service"
  ' _ "$stamp" "$service" "${pending[@]}"

  local i
  for (( i = 1; i < ${#pending[@]}; i += 2 )); do echo "copied   ${pending[i]}"; done
  [[ -z "$service" ]] || echo "restarted $service"
}

# Puts back what each file replaced (its oldest .bak, the original) or deletes
# it, then restarts the app's service.
remove_system() {
  local app="${1#system/etc/}"
  local targets=() src dest
  while IFS= read -r -d '' src; do
    dest="/${src#"$repo"/system/}"
    [[ -e $dest ]] && targets+=("$dest")
  done < <(system_files "$1")
  if (( ${#targets[@]} == 0 )); then
    echo "ok       /etc/$app (nothing to remove)"
    return 0
  fi

  local service=""
  systemctl cat "$app.service" >/dev/null 2>&1 && service="$app.service"

  $SUDO bash -c '
    service="$1"; shift
    for dest in "$@"; do
      backup=$(ls -1d "$dest".bak.* 2>/dev/null | sort -V | head -1)
      if [[ -n $backup ]]; then mv -f "$backup" "$dest"; echo "restored $dest"
      else rm -f "$dest"; echo "removed  $dest"; fi
    done
    [[ -z "$service" ]] || systemctl restart "$service"
  ' _ "$service" "${targets[@]}"
  [[ -z "$service" ]] || echo "restarted $service"
}

# ---------------------------------------------------------------- borders

# The gradient's colors live in ~/.config/witchers-tweaks/border.conf (default
# purple): witchers-tweaks.lua reads them, and the witcher.border-colors
# plugin's bin/border-colors writes the matching Omarchy shell template (so
# popups, notifications and the lock screen share the gradient) and rebuilds
# the theme when it changes. Its Picker.qml is Configure > Borders.
border_colors="$HOME/.config/omarchy/plugins/witcher.border-colors/bin/border-colors"
border_template="$HOME/.config/omarchy/themed/shell.hyprland.toml.tpl"

border_template_ours() {
  grep -qsF "tweaks: generated by border-colors" "$border_template"
}

# The spinning gradient runs on a timer inside Hyprland, which outlives the
# config; removal stops it. Adding needs nothing: the config starts it.
stop_border_spin() {
  if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
    hyprctl eval 'if _G.witcher_border_timer then _G.witcher_border_timer:set_enabled(false); _G.witcher_border_timer = nil end; _G.witcher_border_tick = nil' >/dev/null
    echo "stopped  spinning border"
    reload_hypr=true
  fi
}

configure_borders() {
  if ! shell_running; then
    echo "The border picker runs in the Omarchy shell, which isn't running." >&2
    return 1
  fi
  omarchy-shell shell summon witcher.border-colors '{}' >/dev/null
  echo "Pick the colors in the window that just opened (Enter saves, Esc cancels)."
}

# ---------------------------------------------------------------- agent widget

# The widget embeds a terminal from the qmltermwidget package. It only reads
# color schemes from its own folder, so link a scheme there that
# bin/terminal-colors regenerates from the current Omarchy theme.
agent_terminal_scheme=/usr/lib/qt6/qml/QMLTermWidget/color-schemes/Omarchy.colorscheme

setup_agent_terminal() {
  if pacman -Q qmltermwidget >/dev/null 2>&1; then
    echo "ok       qmltermwidget"
  else
    omarchy pkg add qmltermwidget
    echo "installed qmltermwidget"
    restart_shell=true
  fi

  local scheme
  scheme=$("$HOME/.config/omarchy/plugins/witcher.agents/bin/terminal-colors")
  if [[ "$(readlink "$agent_terminal_scheme")" == "$scheme" ]]; then
    echo "ok       $agent_terminal_scheme"
  else
    $SUDO ln -sfn "$scheme" "$agent_terminal_scheme"
    echo "linked   $agent_terminal_scheme"
    restart_shell=true
  fi
}

# qmltermwidget itself stays: it's an ordinary package something else may use.
remove_agent_terminal() {
  if [[ -L $agent_terminal_scheme ]]; then
    $SUDO rm -f "$agent_terminal_scheme"
    echo "removed  $agent_terminal_scheme"
  else
    echo "ok       $agent_terminal_scheme (not there)"
  fi
  echo "note     qmltermwidget stays installed (omarchy pkg remove qmltermwidget to drop it)"
}

# Point the bar's agents slot at the widget (a clone of omarchy.agents), or add
# it next to the tray when the bar has no agents slot.
use_agent_chat_widget() {
  edit_shell_config "bar uses witcher.agents" '
    if any(.bar.layout[]?[]?; .id == "witcher.agents") then .
    elif any(.bar.layout[]?[]?; .id == "omarchy.agents") then
      .bar.layout |= with_entries(.value |= map(if .id == "omarchy.agents" then .id = "witcher.agents" else . end))
    else
      (.bar.layout.right // []) as $right
      | ([$right | to_entries[] | select(.value.id == "omarchy.tray") | .key] | first // (($right | length) - 1)) as $at
      | .bar.layout.right = $right[:$at + 1] + [{id: "witcher.agents"}] + $right[$at + 1:]
    end'
}

restore_agent_widget() {
  edit_shell_config "bar uses omarchy.agents again" '
    .bar.layout |= with_entries(.value |= map(if .id == "witcher.agents" then .id = "omarchy.agents" else . end))'
}

# ---------------------------------------------------------------- shell.json

# ~/.config/omarchy/shell.json is the user's own bar layout; these steps edit
# it in place with a jq filter, and the shell hot-reloads it. Prints "ok" when
# the filter changes nothing, otherwise writes it (starting from Omarchy's
# defaults if there's no file yet) and prints the message.
shell_config="$HOME/.config/omarchy/shell.json"

edit_shell_config() {
  local message="$1" filter="$2"
  shift 2
  if [[ ! -f $shell_config ]]; then
    mkdir -p "$(dirname "$shell_config")"
    cp "$OMARCHY_PATH/config/omarchy/shell.json" "$shell_config"
  fi
  local current next
  current=$(jq . "$shell_config")
  next=$(jq "$@" "$filter" <<<"$current")
  if [[ $next == "$current" ]]; then
    echo "ok       $message"
  else
    printf '%s\n' "$next" >"$shell_config.tmp.$stamp"
    mv "$shell_config.tmp.$stamp" "$shell_config"
    echo "set      $message"
  fi
}

# True when the jq expression holds for shell.json.
shell_config_has() {
  [[ -f $shell_config ]] && jq -e "$@" "$shell_config" >/dev/null 2>&1
}

shell_running() {
  pgrep -f "quickshell -n -p .*omarchy/shell" >/dev/null
}

# Moves the clock to the front of the center section, keeping its settings.
center_clock() {
  edit_shell_config "clock in the middle of the bar" '
    if any(.bar.layout.center[]?; .id == "omarchy.clock") then . else
      (first(.bar.layout[]?[]? | select(.id == "omarchy.clock")) // {id: "omarchy.clock"}) as $clock
      | .bar.layout |= with_entries(.value |= map(select(.id != "omarchy.clock")))
      | .bar.layout.center = [$clock] + (.bar.layout.center // [])
    end'
}

# Back where Omarchy has it: on the right, before the keyboard layout.
uncenter_clock() {
  edit_shell_config "clock back on the right of the bar" '
    if any(.bar.layout.center[]?; .id == "omarchy.clock") | not then . else
      first(.bar.layout.center[] | select(.id == "omarchy.clock")) as $clock
      | .bar.layout.center |= map(select(.id != "omarchy.clock"))
      | (.bar.layout.right // []) as $right
      | ([$right | to_entries[] | select(.value.id == "omarchy.keyboard-layout") | .key] | first // ($right | length)) as $at
      | .bar.layout.right = $right[:$at] + [$clock] + $right[$at:]
    end'
}

# The stock power widget has the percentage built in (right-click toggles it);
# this just turns it on.
show_battery_percent() {
  if ! shell_config_has 'any(.bar.layout[]?[]?; .id == "omarchy.power")'; then
    echo "skip     battery percentage (omarchy.power isn't on the bar)"
    return 0
  fi
  edit_shell_config "battery percentage" '
    .bar.layout |= with_entries(.value |= map(if .id == "omarchy.power" then .showPercentage = true else . end))'
}

hide_battery_percent() {
  edit_shell_config "no battery percentage" '
    .bar.layout |= with_entries(.value |= map(if .id == "omarchy.power" then del(.showPercentage) else . end))'
}

# The bell goes on the right, before Bluetooth (or at the end without it).
use_notification_panel() {
  edit_shell_config "notifications bell on the bar" '
    if any(.bar.layout[]?[]?; .id == "witcher.notifications") then . else
      (.bar.layout.right // []) as $right
      | ([$right | to_entries[] | select(.value.id == "omarchy.bluetooth") | .key] | first // ($right | length)) as $at
      | .bar.layout.right = $right[:$at] + [{id: "witcher.notifications"}] + $right[$at:]
    end'
}

# Also drops the panel's own copy of past notifications (Omarchy's history
# is untouched).
remove_notification_panel() {
  edit_shell_config "no notifications bell on the bar" '
    .bar.layout |= with_entries(.value |= map(select(.id != "witcher.notifications")))'
  local store="${XDG_STATE_HOME:-$HOME/.local/state}/witcher/notifications"
  if [[ -d $store ]]; then
    rm -rf "$store"
    rmdir "$(dirname "$store")" 2>/dev/null || true
    echo "removed  the panel's saved notifications"
  fi
}

# Services and overlays are switched on by an entry in plugins[]; extra keys
# on the entry are their settings.
enable_service() {
  local id="$1" settings="$2" message="$3"
  edit_shell_config "$message" '
    .plugins = (.plugins // [])
    | if any(.plugins[]; .id == $id)
      then .plugins |= map(if .id == $id then . + $settings else . end)
      else .plugins += [{id: $id} + $settings]
      end' --arg id "$id" --argjson settings "$settings"
}

disable_service() {
  local id="$1" message="$2"
  edit_shell_config "$message" '.plugins = ((.plugins // []) | map(select(.id != $id)))' --arg id "$id"
}

service_enabled() {
  shell_config_has --arg id "$1" 'any(.plugins[]?; .id == $id)'
}

service_setting() {
  local id="$1" key="$2" fallback="$3"
  jq -r --arg id "$id" --arg key "$key" --arg fallback "$fallback" \
    'first(.plugins[]? | select(.id == $id) | .[$key]) // $fallback' "$shell_config" 2>/dev/null || echo "$fallback"
}

# ---------------------------------------------------------------- choices

# Asks for one of a fixed set of values: gum when there is one, else a
# prompt. Without a terminal it keeps the current value. Prints the choice.
#   pick_value <question> <unit> <current> <values...>
pick_value() {
  local question="$1" unit="$2" current="$3"
  shift 3
  local choices=("$@") choice
  [[ " ${choices[*]} " == *" $current "* ]] || current="${choices[0]}"

  if [[ ! -t 0 ]]; then
    echo "$current"
  elif command -v gum >/dev/null; then
    local labels=()
    for choice in "${choices[@]}"; do labels+=("$choice$unit"); done
    choice=$(gum choose --header "$question" --selected "$current$unit" "${labels[@]}")
    [[ -n $choice ]] || choice="$current$unit"
    echo "${choice%"$unit"}"
  else
    read -rp "$question (${choices[*]}) [$current] " choice </dev/tty
    choice=${choice%"$unit"}
    [[ " ${choices[*]} " == *" $choice "* ]] || choice=$current
    echo "$choice"
  fi
}

# An environment override (SUSPEND_MINUTES, NOTIFY_SECONDS) skips the question.
env_choice() {
  local name="$1" value="$2"
  shift 2
  if [[ " $* " != *" $value "* ]]; then
    echo "$name must be one of: $*" >&2
    return 1
  fi
  echo "$value"
}

# ---------------------------------------------------------------- suspend

suspend_choices=(1 5 10 15 30 60)

pick_suspend_minutes() {
  if [[ -n ${SUSPEND_MINUTES:-} ]]; then
    env_choice SUSPEND_MINUTES "$SUSPEND_MINUTES" "${suspend_choices[@]}"
  else
    pick_value "Suspend after how long idle?" m "$(service_setting witcher.idle-suspend minutes 5)" "${suspend_choices[@]}"
  fi
}

# Suspend replaces the screensaver: Omarchy's own toggle turns that off, and
# witcher.idle-suspend does the suspending (the lock still comes first, via
# Omarchy's sleep-lock).
setup_idle_suspend() {
  local minutes
  minutes=$(pick_suspend_minutes)
  enable_service witcher.idle-suspend "{\"minutes\":$minutes}" "suspend after ${minutes}m idle"
  if omarchy-toggle-enabled screensaver-off; then
    echo "ok       screensaver off"
  else
    omarchy-toggle screensaver-off on
    echo "set      screensaver off"
  fi
}

remove_idle_suspend() {
  disable_service witcher.idle-suspend "no suspend when idle"
  if omarchy-toggle-enabled screensaver-off; then
    omarchy-toggle screensaver-off off
    echo "set      screensaver back on"
  else
    echo "ok       screensaver on"
  fi
}

configure_idle_suspend() {
  local minutes
  minutes=$(pick_suspend_minutes)
  enable_service witcher.idle-suspend "{\"minutes\":$minutes}" "suspend after ${minutes}m idle"
}

# ---------------------------------------------------------------- notifications

notify_choices=(3 5 8 10 15)

pick_notify_seconds() {
  if [[ -n ${NOTIFY_SECONDS:-} ]]; then
    env_choice NOTIFY_SECONDS "$NOTIFY_SECONDS" "${notify_choices[@]}"
  else
    pick_value "Notifications leave the screen after?" s "$(service_setting witcher.notify-timeout seconds 5)" "${notify_choices[@]}"
  fi
}

# Installs with the current setting (5 seconds the first time) without asking;
# --configure changes it.
setup_notify_timeout() {
  local seconds
  seconds=$(service_setting witcher.notify-timeout seconds 5)
  [[ -n ${NOTIFY_SECONDS:-} ]] && seconds=$(pick_notify_seconds)
  enable_service witcher.notify-timeout "{\"seconds\":$seconds}" "notifications leave after ${seconds}s"
}

configure_notify_timeout() {
  local seconds
  seconds=$(pick_notify_seconds)
  enable_service witcher.notify-timeout "{\"seconds\":$seconds}" "notifications leave after ${seconds}s"
}

# ---------------------------------------------------------------- dock

# Each setting: key | environment override | label | kind | spec.
#   choice  spec is value|label;value|label... (the first is the default)
#   slider  spec is min:max:step[:default] (a percentage, 0 by default)
#   border  the dock's border: the windows' gradient, custom colors, solid, none
# Size to Show suggested and recent apps are macOS's Desktop & Dock options.
dock_settings=(
  "size|DOCK_SIZE|Size|choice|48|Medium (48 px);32|Smallest (32 px);40|Small (40 px);56|Large (56 px);64|Larger (64 px);80|Largest (80 px)"
  "magnification|DOCK_MAGNIFICATION|Magnification|choice|0|Off;64|Small (64 px);80|Medium (80 px);96|Large (96 px);128|Largest (128 px)"
  "position|DOCK_POSITION|Position on screen|choice|bottom|Bottom;left|Left;right|Right"
  "minimize|DOCK_MINIMIZE|Minimize windows into application icon|choice|false|No: minimized windows get their own place;true|Yes: into their app's icon"
  "hide|DOCK_HIDE|Automatically hide and show the Dock|choice|auto|Yes: until the cursor touches the screen edge;never|No: always shown, windows tile around it;smart|Only while a window would sit under it"
  "animate|DOCK_ANIMATE|Animate opening applications|choice|true|Yes: icons bounce while their app opens;false|No"
  "indicators|DOCK_INDICATORS|Show indicators for open applications|choice|true|Yes: a dot under running apps;false|No"
  "recents|DOCK_RECENTS|Show suggested and recent apps in Dock|choice|true|Yes: after a divider;false|No"
  "click|DOCK_CLICK|Clicking the app you're in|choice|cycle|Goes to its next window;focus|Stays on its last used window"
  "transparency|DOCK_TRANSPARENCY|Dock transparency|slider|0:90:5"
  "appsTransparency|DOCK_APPS_TRANSPARENCY|App drawer transparency|slider|0:90:5"
  "roundness|DOCK_ROUNDNESS|Corner rounding (dock and app drawer; same scale as windows)|slider|0:100:5:60"
  "border|DOCK_BORDER|Dock border|border|windows|Same gradient as the windows;custom|Custom gradient colors;solid|One solid color (no gradient);none|No border"
)

dock_field() { cut -d'|' -f"$2" <<<"$1"; }
dock_spec() { cut -d'|' -f5- <<<"$1"; }

# A saved dock setting as text ("" when unset). Not service_setting: its //
# would read a saved false as unset.
dock_get() {
  jq -r --arg k "$1" 'first(.plugins[]? | select(.id == "witcher.dock") | .[$k]) | if . == null then "" elif type == "array" then join(" ") else tostring end' "$shell_config" 2>/dev/null || true
}

# Saves a setting (a JSON value, or null to remove it) without a word, for
# live previews.
dock_put() {
  local key="$1" value="$2" next
  [[ -f $shell_config ]] || return 0
  next=$(jq --arg k "$key" --argjson v "$value" \
    '.plugins |= map(if .id == "witcher.dock" then (if $v == null then del(.[$k]) else .[$k] = $v end) else . end)' "$shell_config") || return 1
  printf '%s\n' "$next" >"$shell_config.tmp.$stamp"
  mv "$shell_config.tmp.$stamp" "$shell_config"
}

# JSON for a setting's text value: numbers and true/false as such.
dock_json() {
  if [[ $1 =~ ^([0-9]+|true|false)$ ]]; then echo "$1"; else jq -n --arg v "$1" '$v'; fi
}

# Shows the dock (or "apps": the App drawer) while a setting is changed, so
# the change can be seen; "off" hides it again.
dock_peek() {
  if [[ $1 == off ]]; then dock_put peek null; else dock_put peek "\"$1\""; fi
}

# The label of a setting's current value, for the menu.
dock_current_label() {
  local entry="$1" key kind spec current pair pairs=()
  key=$(dock_field "$entry" 1)
  kind=$(dock_field "$entry" 4)
  spec=$(dock_spec "$entry")
  current=$(dock_get "$key")
  case $kind in
    slider)
      local default
      IFS=':' read -r _ _ _ default <<<"$spec"
      echo "${current:-${default:-0}}%"
      ;;
    border|choice)
      IFS=';' read -ra pairs <<<"$spec"
      [[ -n $current ]] || current="${pairs[0]%%|*}"
      for pair in "${pairs[@]}"; do
        if [[ ${pair%%|*} == "$current" ]]; then
          local label="${pair#*|}"
          [[ $kind == border && $current =~ ^(custom|solid)$ ]] && label="$label ($(dock_get borderColors))"
          echo "$label"
          return
        fi
      done
      echo "$current"
      ;;
  esac
}

# A colored block for a hex color, in terminals that do true color.
swatch() {
  local c=${1#\#}
  printf '\e[48;2;%d;%d;%dm      \e[0m' "0x${c:0:2}" "0x${c:2:2}" "0x${c:4:2}"
}

# Asks for a hex color; prints it (#rrggbb), or the current one when the
# answer isn't a color.
ask_color() {
  local question="$1" current="$2" answer
  if command -v gum >/dev/null; then
    answer=$(gum input --header "$question (6 hex digits)" --value "$current" --placeholder "#a855f7") || answer=$current
  else
    read -rp "$question (6 hex digits) [$current] " answer </dev/tty || answer=$current
  fi
  answer=${answer#\#}
  if [[ $answer =~ ^[0-9a-fA-F]{6}$ ]]; then echo "#${answer,,}"; else echo "$current"; fi
}

# A slider in the terminal: left/right (or h/l) move it and each step runs
# the preview command with the value added, so it shows straight away; Enter
# keeps it, Esc puts the start value back. Prints the value.
#   term_slider <label> <min> <max> <step> <value> <unit> <preview command...>
term_slider() {
  local label="$1" min="$2" max="$3" step="$4" value="$5" unit="$6"
  shift 6
  local original=$value k rest width=30 filled bar i
  printf '%s   ←/→ change, Enter keeps, Esc cancels\n' "$label" >/dev/tty
  tput civis 2>/dev/null >/dev/tty || true
  while true; do
    filled=$(( (value - min) * width / (max - min) ))
    bar=""
    for (( i = 0; i < width; i++ )); do if (( i < filled )); then bar+="█"; else bar+="░"; fi; done
    printf '\r  %s %3d%s  ' "$bar" "$value" "$unit" >/dev/tty
    IFS= read -rsn1 k </dev/tty || break
    case $k in
      $'\e')
        rest=""
        read -rsn2 -t 0.05 rest </dev/tty || true
        case $rest in
          "[D") k=left ;;
          "[C") k=right ;;
          "") value=$original; "$@" "$value"; break ;;
          *) continue ;;
        esac
        ;;
      h) k=left ;;
      l) k=right ;;
      "") break ;;
      *) continue ;;
    esac
    if [[ $k == left ]]; then value=$(( value - step < min ? min : value - step )); fi
    if [[ $k == right ]]; then value=$(( value + step > max ? max : value + step )); fi
    "$@" "$value" >/dev/null 2>&1 || true
  done
  tput cnorm 2>/dev/null >/dev/tty || true
  printf '\n' >/dev/tty
  echo "$value"
}

# A dock percentage, on the terminal slider, previewed on the dock (or the
# App drawer for its own setting).
#   dock_slider <key> <label> <min> <max> <step> [default]
dock_slider() {
  local key="$1" label="$2" min="$3" max="$4" step="$5" default="${6:-$3}" value
  [[ -t 0 ]] || return 0
  value=$(dock_get "$key")
  [[ $value =~ ^[0-9]+$ ]] || value=$default
  [[ $key == appsTransparency ]] && dock_peek apps || dock_peek dock
  value=$(term_slider "$label" "$min" "$max" "$step" "$value" "%" dock_put "$key")
  dock_put "$key" "$value"
  dock_peek off
  echo "set      $label: $value%"
}

# The dock's border: which kind, then its colors (previewed on the dock).
dock_border() {
  local entry="$1" mode colors=() saved=() c i names=("First" "Second" "Third") window
  mode=$(pick_labeled "Dock border" "$(dock_get border)" "$(dock_spec "$entry")")
  dock_put border "$(dock_json "$mode")"
  if [[ $mode == custom || $mode == solid ]]; then
    read -ra saved <<<"$(dock_get borderColors)"
    colors=("${saved[@]}")
    # Start from the window border's colors.
    if (( ${#colors[@]} < 3 )) && window=$("$border_colors" get 2>/dev/null); then
      read -ra c <<<"$window"
      colors=("#${c[0]}" "#${c[1]}" "#${c[2]}")
    fi
    (( ${#colors[@]} >= 3 )) || colors=("#c4b5fd" "#a855f7" "#da70d6")
    dock_peek dock
    local count=3
    if [[ $mode == solid ]]; then
      count=1
      # A saved solid color, else the middle of the gradient.
      if (( ${#saved[@]} == 1 )); then colors=("${saved[0]}"); else colors=("${colors[1]}"); fi
    fi
    for (( i = 0; i < count; i++ )); do
      if [[ $mode == solid ]]; then
        colors[i]=$(ask_color "Border color" "${colors[i]}")
      else
        colors[i]=$(ask_color "${names[i]} gradient color" "${colors[i]}")
      fi
      printf '  %s %s\n' "$(swatch "${colors[i]}")" "${colors[i]}" >/dev/tty
      dock_put borderColors "$(printf '%s\n' "${colors[@]:0:count}" | jq -R . | jq -sc .)"
    done
    dock_peek off
  fi
  echo "set      Dock border: $(dock_current_label "$entry")"
}

# Asks for one setting and saves it.
dock_ask() {
  local entry="$1" key label kind value
  key=$(dock_field "$entry" 1)
  label=$(dock_field "$entry" 3)
  kind=$(dock_field "$entry" 4)
  case $kind in
    choice)
      value=$(pick_labeled "$label" "$(dock_get "$key")" "$(dock_spec "$entry")")
      dock_put "$key" "$(dock_json "$value")"
      echo "set      $label: $(dock_current_label "$entry")"
      ;;
    slider)
      local min max step default
      IFS=':' read -r min max step default <<<"$(dock_spec "$entry")"
      dock_slider "$key" "$label" "$min" "$max" "$step" "$default"
      ;;
    border) dock_border "$entry" ;;
  esac
}

# Settings given in the environment (DOCK_SIZE=64 and so on), checked and
# saved. Returns 1 when there were none.
dock_env_settings() {
  local entry key env kind spec value any=1 allowed=() pairs=() pair min max step
  for entry in "${dock_settings[@]}"; do
    key=$(dock_field "$entry" 1)
    env=$(dock_field "$entry" 2)
    kind=$(dock_field "$entry" 4)
    spec=$(dock_spec "$entry")
    value=${!env:-}
    [[ -n $value ]] || continue
    any=0
    if [[ $kind == slider ]]; then
      IFS=':' read -r min max step _ <<<"$spec"
      [[ $value =~ ^[0-9]+$ ]] && (( value >= min && value <= max )) || { echo "$env must be $min-$max" >&2; return 2; }
    else
      allowed=()
      IFS=';' read -ra pairs <<<"$spec"
      for pair in "${pairs[@]}"; do allowed+=("${pair%%|*}"); done
      value=$(env_choice "$env" "$value" "${allowed[@]}") || return 2
    fi
    dock_put "$key" "$(dock_json "$value")"
    echo "set      $(dock_field "$entry" 3): $(dock_current_label "$entry")"
  done
  if [[ -n ${DOCK_BORDER_COLORS:-} ]]; then
    local list=() c
    IFS=', ' read -ra list <<<"$DOCK_BORDER_COLORS"
    for c in "${list[@]}"; do [[ ${c#\#} =~ ^[0-9a-fA-F]{6}$ ]] || { echo "DOCK_BORDER_COLORS: not a color: $c" >&2; return 2; }; done
    dock_put borderColors "$(printf '#%s\n' "${list[@]#\#}" | jq -R . | jq -sc .)"
    any=0
  fi
  return $any
}

# Desktop entry ids for a first dock: the default browser, the default
# terminal and Files, the ones that exist.
dock_default_pins() {
  local ids=() id dir
  id=$(xdg-settings get default-web-browser 2>/dev/null || true)
  [[ -n $id ]] && ids+=("${id%.desktop}")
  id=$(xdg-terminal-exec --print-id 2>/dev/null | head -1 || true)
  [[ -n $id ]] && ids+=("${id%.desktop}")
  ids+=(org.gnome.Nautilus)
  local found=() data_dirs
  IFS=':' read -ra data_dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for id in "${ids[@]}"; do
    for dir in "${data_dirs[@]}"; do
      if [[ -f $dir/applications/$id.desktop ]]; then
        [[ " ${found[*]} " == *" $id "* ]] || found+=("$id")
        break
      fi
    done
  done
  (( ${#found[@]} )) || { echo '[]'; return; }
  printf '%s\n' "${found[@]}" | jq -R . | jq -sc .
}

# Adding the dock asks nothing: it starts from the defaults (and a few kept
# apps), and Configure > Dock changes any one setting.
setup_dock() {
  local settings='{}'
  if ! shell_config_has 'any(.plugins[]?; .id == "witcher.dock" and has("pinned"))'; then
    settings=$(jq -c --argjson pins "$(dock_default_pins)" '{pinned: $pins}' <<<"{}")
  fi
  enable_service witcher.dock "$settings" "dock"
  # "show" was a setting of the first version of the dock; it's gone.
  edit_shell_config "dock settings tidy" '.plugins |= map(if .id == "witcher.dock" then del(.show, .peek) else . end)'
  local status=0
  dock_env_settings || status=$?
  (( status == 2 )) && return 1
  return 0
}

# A list of the settings with their current values: pick one, change it,
# back to the list; Done (or Esc) leaves.
configure_dock() {
  local status=0
  dock_env_settings || status=$?
  (( status == 2 )) && return 1
  (( status == 0 )) && return 0
  if [[ ! -t 0 ]]; then
    for entry in "${dock_settings[@]}"; do
      printf '%-40s %s\n' "$(dock_field "$entry" 3)" "$(dock_current_label "$entry")"
    done
    return 0
  fi
  trap 'dock_peek off; tput cnorm 2>/dev/null >/dev/tty || true' EXIT
  local entry labels choice i
  while true; do
    labels=()
    for entry in "${dock_settings[@]}"; do
      labels+=("$(printf '%-40s %s' "$(dock_field "$entry" 3)" "$(dock_current_label "$entry")")")
    done
    labels+=("Done")
    if command -v gum >/dev/null; then
      choice=$(gum choose --header "Dock settings: pick one to change" "${labels[@]}") || choice="Done"
    else
      echo "Dock settings:" >/dev/tty
      for i in "${!labels[@]}"; do echo "  $((i + 1))) ${labels[i]}" >/dev/tty; done
      read -rp "Number: " i </dev/tty || i=""
      choice="Done"
      [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#labels[@]} )) && choice="${labels[i - 1]}"
    fi
    [[ -z $choice || $choice == "Done" ]] && break
    for i in "${!labels[@]}"; do
      [[ ${labels[i]} == "$choice" ]] && dock_ask "${dock_settings[i]}"
    done
  done
  trap - EXIT
  dock_peek off
}

# ---------------------------------------------------------------- window corners

rounding_conf="$HOME/.config/witchers-tweaks/rounding.conf"

# Window corners go from 0 (sharp) to 100 %, a 32 px radius: the same scale as
# the dock's corner rounding, so equal percentages match.
rounding_px() { echo $(( ($1 * 32 + 50) / 100 )); }

# The saved percentage, else the nearest to what Hyprland uses now.
window_rounding() {
  local percent px
  percent=$(sed -n 's/^[[:space:]]*roundness[[:space:]]*=[[:space:]]*\([0-9]\+\).*/\1/p' "$rounding_conf" 2>/dev/null | head -1)
  if [[ -z $percent ]]; then
    # rounding=<px> is what the first version of the tweak saved.
    px=$(sed -n 's/^[[:space:]]*rounding[[:space:]]*=[[:space:]]*\([0-9]\+\).*/\1/p' "$rounding_conf" 2>/dev/null | head -1)
    [[ -n $px ]] || px=$(hyprctl getoption decoration:rounding -j 2>/dev/null | jq -r '.int // empty' 2>/dev/null)
    percent=$(( (${px:-0} * 100 + 16) / 32 ))
    (( percent > 100 )) && percent=100
  fi
  echo "$percent"
}

preview_rounding() {
  hyprctl eval "hl.config({ decoration = { rounding = $(rounding_px "$1") } })" >/dev/null
}

save_rounding() {
  mkdir -p "$(dirname "$rounding_conf")"
  printf 'roundness=%s\n' "$1" >"$rounding_conf"
}

# Adding the tweak keeps the current corners until they're configured (or
# asks right away in a terminal).
setup_window_rounding() {
  if [[ -n ${WINDOW_ROUNDING:-} ]]; then
    [[ $WINDOW_ROUNDING =~ ^[0-9]+$ ]] && (( WINDOW_ROUNDING <= 100 )) || { echo "WINDOW_ROUNDING must be 0-100 (%)" >&2; return 1; }
    save_rounding "$WINDOW_ROUNDING"
    echo "set      window corners: $WINDOW_ROUNDING%"
  elif grep -qs '^[[:space:]]*roundness' "$rounding_conf"; then
    echo "ok       window corners: $(window_rounding)%"
  elif [[ -t 0 && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    configure_window_rounding
  else
    save_rounding "$(window_rounding)"
    echo "set      window corners: $(window_rounding)% (change in Configure > Corners)"
  fi
}

remove_window_rounding() {
  if [[ -f $rounding_conf ]]; then
    rm -f "$rounding_conf"
    echo "removed  ~/.config/witchers-tweaks/rounding.conf"
  fi
}

configure_window_rounding() {
  local percent
  if [[ -n ${WINDOW_ROUNDING:-} || ! -t 0 ]]; then
    setup_window_rounding
    return
  fi
  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    echo "Window corners need a running Hyprland session." >&2
    return 1
  fi
  percent=$(term_slider "Window corner rounding (same scale as the dock's)" 0 100 5 "$(window_rounding)" "%" preview_rounding)
  save_rounding "$percent"
  preview_rounding "$percent"
  echo "set      window corners: $percent%"
}

# ---------------------------------------------------------------- monitors

monitor_setup="$repo/monitors/monitor-setup"

configure_monitors() {
  if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    echo "The monitor setup needs a running Hyprland session." >&2
    return 1
  fi
  "$monitor_setup"
}

# ---------------------------------------------------------------- auto-hide

autohide_script="$HOME/.local/share/witchers-tweaks/autohide-bar"

autohide_running() {
  pgrep -f "witchers-tweaks/autohide-bar|\.config/topbar/autohide\.sh" >/dev/null
}

# witchers-tweaks.lua starts it at login; this starts it now too.
start_autohide() {
  if autohide_running; then
    echo "ok       top bar auto-hide running"
  elif [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -x $autohide_script ]]; then
    setsid -f "$autohide_script" >/dev/null 2>&1 </dev/null
    echo "started  top bar auto-hide"
  else
    echo "note     top bar auto-hide starts at the next login"
  fi
}

# Runs before the script is unlinked: stop the loop and show the bar.
stop_autohide() {
  if autohide_running; then
    pkill -f "witchers-tweaks/autohide-bar" || true
    echo "stopped  top bar auto-hide"
  else
    echo "ok       top bar auto-hide not running"
  fi
  if command -v omarchy-toggle-bar >/dev/null && omarchy-toggle-enabled bar-off; then
    omarchy-toggle-bar off
    echo "set      top bar shown"
  fi
}

# ---------------------------------------------------------------- SMI driver

# Silicon Motion SM77x USB display driver, vendored in smidriver/driver/ from
# github.com/xxwitcher/SiliconMotion-Driver-Fix: SiliconMotion's installer with
# its bundled EVDI build removed (it fails on current kernels), so it runs on
# the system evdi-dkms instead. That needs dkms, evdi-dkms (AUR) and the
# headers for the running kernel first.
smi_driver_dir="$repo/smidriver/driver"
smi_nullfix_lib=/usr/local/lib/libevdi-nullfix.so
smi_nullfix_dropin=/etc/systemd/system/smiusbdisplay.service.d/nullfix.conf

smi_installed() {
  [[ -x /opt/siliconmotion/SMIUSBDisplayManager || -e $smi_nullfix_lib ]]
}

install_smi_driver() {
  local kernel_pkg
  kernel_pkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -1)
  if [[ -z $kernel_pkg ]]; then
    echo "skip     smi driver (can't tell which package owns the running kernel)" >&2
    return 0
  fi

  local needed=() pkg
  for pkg in dkms "$kernel_pkg-headers"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || needed+=("$pkg")
  done
  # A stale package database makes these 404; Omarchy wants system updates to
  # go through `omarchy update`, so point there instead of syncing here.
  local stale="run \`omarchy update\` and re-run: ./install.sh smidriver"
  if (( ${#needed[@]} )); then
    if ! omarchy pkg add "${needed[@]}"; then
      echo "failed   installing ${needed[*]} — $stale" >&2
      return 0
    fi
    echo "installed ${needed[*]}"
  else
    echo "ok       dkms $kernel_pkg-headers"
  fi

  if pacman -Q evdi-dkms >/dev/null 2>&1; then
    echo "ok       evdi-dkms"
  else
    if ! omarchy pkg aur add evdi-dkms; then
      echo "failed   installing evdi-dkms — $stale" >&2
      return 0
    fi
    echo "installed evdi-dkms"
  fi

  if [[ -x /opt/siliconmotion/SMIUSBDisplayManager ]]; then
    echo "ok       SiliconMotion driver (reinstall: sudo smi-installer uninstall, reboot, re-run)"
  # The driver installer copies its files by relative path, so it has to run
  # from its own folder.
  elif $SUDO bash -c 'cd "$1" && ./install.sh install' _ "$smi_driver_dir"; then
    echo "installed SiliconMotion driver"
  else
    echo "failed   SiliconMotion driver (see its output above; if it asks for a reboot, reboot and re-run)" >&2
    return 0
  fi

  install_smi_nullfix
}

# SMIUSBDisplayManager calls evdi_open_attached_to(NULL), which crashes in
# upstream libevdi (strlen on NULL); SiliconMotion's bundled EVDI, which the
# fix above skips, tolerated it. Preload a shim routing that call to the
# NULL-safe evdi_open_attached_to_fixed. See smidriver/evdi-nullfix.c.
install_smi_nullfix() {
  local build
  build=$(mktemp -d)
  gcc -shared -fPIC -O2 -o "$build/libevdi-nullfix.so" "$repo/smidriver/evdi-nullfix.c" -levdi

  if cmp -s "$build/libevdi-nullfix.so" "$smi_nullfix_lib" && cmp -s "$repo/smidriver/nullfix.conf" "$smi_nullfix_dropin"; then
    echo "ok       evdi null fix"
  else
    $SUDO bash -c '
      install -D -m 755 "$1" "$2"
      install -D -m 644 "$3" "$4"
      systemctl daemon-reload
    ' _ "$build/libevdi-nullfix.so" "$smi_nullfix_lib" "$repo/smidriver/nullfix.conf" "$smi_nullfix_dropin"
    echo "installed evdi null fix ($smi_nullfix_lib + service drop-in)"
  fi
  rm -rf "$build"

  # The driver's udev rule starts the service when the adapter is plugged in.
  # If it already is, (re)start it now so the monitors come up without a
  # reboot or replug, clearing any earlier crash-loop state.
  if smi_adapter_present; then
    if systemctl is-active -q smiusbdisplay && [[ $(systemctl show -p NRestarts --value smiusbdisplay) == 0 ]] \
      && [[ $(systemctl show -p ActiveEnterTimestampMonotonic --value smiusbdisplay) -gt 0 ]] \
      && systemctl show -p Environment --value smiusbdisplay | grep -q libevdi-nullfix; then
      echo "ok       smiusbdisplay running"
    else
      $SUDO bash -c 'systemctl reset-failed smiusbdisplay 2>/dev/null; systemctl restart smiusbdisplay'
      echo "started  smiusbdisplay (adapter is plugged in)"
    fi
  else
    echo "note     plug the adapter in to start the driver (reboot if its monitors don't come up)"
  fi
}

# SiliconMotion's own uninstaller removes the driver; the null-fix shim and
# its drop-in go too. The dkms, evdi-dkms and kernel header packages stay.
remove_smi_driver() {
  if ! smi_installed; then
    echo "ok       SiliconMotion driver (not installed)"
    return 0
  fi
  if [[ -x /opt/siliconmotion/SMIUSBDisplayManager ]] && command -v smi-installer >/dev/null; then
    $SUDO smi-installer uninstall
    echo "removed  SiliconMotion driver"
  fi
  $SUDO bash -c '
    rm -f "$1" "$2"
    rmdir "$(dirname "$2")" 2>/dev/null || true
    systemctl daemon-reload
  ' _ "$smi_nullfix_lib" "$smi_nullfix_dropin"
  echo "removed  evdi null fix"
  echo "note     dkms, evdi-dkms and the kernel headers stay installed (omarchy pkg remove evdi-dkms to drop it); reboot to finish"
}

# ---------------------------------------------------------------- steps

# apply | remove | check for one item. check succeeds when the item is in
# place, fails when it isn't, and returns 2 for items that don't tell (so they
# don't count either way).
step() {
  local action="$1" item="$2"
  case "$action:$item" in
    apply:home/*) link_home "$item" ;;
    remove:home/*) unlink_home "$item" ;;
    check:home/*) home_linked "$item" ;;

    apply:system/*) copy_system "$item" ;;
    remove:system/*) remove_system "$item" ;;
    check:system/*) system_installed "$item" ;;

    apply:hypr:*) enable_hypr "${item#hypr:}" ;;
    remove:hypr:*) disable_hypr "${item#hypr:}" ;;
    check:hypr:*) hypr_enabled "${item#hypr:}" ;;

    apply:@border-shell) "$border_colors" shell-apply ;;
    remove:@border-shell) "$border_colors" shell-remove ;;
    check:@border-shell) border_template_ours ;;

    apply:@border-picker) enable_service witcher.border-colors '{}' "border color picker" ;;
    remove:@border-picker) disable_service witcher.border-colors "no border color picker" ;;
    check:@border-picker) service_enabled witcher.border-colors ;;

    apply:@border-spin) echo "ok       spinning border (witchers-tweaks.lua runs it)" ;;
    remove:@border-spin) stop_border_spin ;;
    check:@border-spin) return 2 ;;

    apply:@agent-terminal) setup_agent_terminal ;;
    remove:@agent-terminal) remove_agent_terminal ;;
    check:@agent-terminal) [[ -L $agent_terminal_scheme ]] ;;

    apply:@agent-bar) use_agent_chat_widget ;;
    remove:@agent-bar) restore_agent_widget ;;
    check:@agent-bar) shell_config_has 'any(.bar.layout[]?[]?; .id == "witcher.agents")' ;;

    apply:@smi-driver) install_smi_driver ;;
    remove:@smi-driver) remove_smi_driver ;;
    check:@smi-driver) smi_installed ;;

    apply:@clock-center) center_clock ;;
    remove:@clock-center) uncenter_clock ;;
    check:@clock-center) shell_config_has 'any(.bar.layout.center[]?; .id == "omarchy.clock")' ;;

    apply:@battery-percent) show_battery_percent ;;
    remove:@battery-percent) hide_battery_percent ;;
    check:@battery-percent) shell_config_has 'any(.bar.layout[]?[]?; .id == "omarchy.power" and .showPercentage == true)' ;;

    apply:@notify-panel) use_notification_panel ;;
    remove:@notify-panel) remove_notification_panel ;;
    check:@notify-panel) shell_config_has 'any(.bar.layout[]?[]?; .id == "witcher.notifications")' ;;

    apply:@notify-timeout) setup_notify_timeout ;;
    remove:@notify-timeout) disable_service witcher.notify-timeout "notifications keep Omarchy's timing" ;;
    check:@notify-timeout) service_enabled witcher.notify-timeout ;;

    apply:@idle-suspend) setup_idle_suspend ;;
    remove:@idle-suspend) remove_idle_suspend ;;
    check:@idle-suspend) service_enabled witcher.idle-suspend ;;

    apply:@overview) enable_service witcher.overview '{}' "window overview" ;;
    remove:@overview) disable_service witcher.overview "no window overview" ;;
    check:@overview) service_enabled witcher.overview ;;

    apply:@window-rounding) setup_window_rounding ;;
    remove:@window-rounding) remove_window_rounding ;;
    check:@window-rounding) [[ -f $rounding_conf ]] ;;

    apply:@dock) setup_dock ;;
    remove:@dock) disable_service witcher.dock "no dock" ;;
    check:@dock) service_enabled witcher.dock ;;

    apply:@autohide) start_autohide ;;
    remove:@autohide) stop_autohide ;;
    check:@autohide) return 2 ;;

    *) echo "unknown step: $action $item" >&2; return 1 ;;
  esac
}

# full, partial or none.
tweak_state() {
  local t item on=0 off=0 status
  t=$(tweak_line "$1") || { echo none; return; }
  for item in $(field "$t" 4); do
    status=0
    step check "$item" || status=$?
    case $status in
      0) on=$((on + 1)) ;;
      2) ;;
      *) off=$((off + 1)) ;;
    esac
  done
  if (( on > 0 && off == 0 )); then echo full
  elif (( on > 0 )); then echo partial
  else echo none
  fi
}

apply_tweaks() {
  local t name item
  for t in "${tweaks[@]}"; do
    name="$(field "$t" 1)"
    [[ " $* " == *" $name "* ]] || continue
    echo "== $name"
    for item in $(field "$t" 4); do step apply "$item"; done
  done
}

# Each tweak's steps in reverse, so its settings leave shell.json before its
# plugin files go, and background loops stop before their scripts do.
remove_tweaks() {
  local t name items i
  for t in "${tweaks[@]}"; do
    name="$(field "$t" 1)"
    [[ " $* " == *" $name "* ]] || continue
    echo "== removing $name"
    read -ra items <<<"$(field "$t" 4)"
    for (( i = ${#items[@]} - 1; i >= 0; i-- )); do step remove "${items[i]}"; done
  done
  tidy_loader
}

# ---------------------------------------------------------------- menu

menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
menu_begin="// >>> witchers-tweaks (managed by the Witcher's Tweaks install.sh; --uninstall takes it out)"
menu_end="// <<< witchers-tweaks"

menu_block() {
  local run
  run() { printf 'omarchy-launch-floating-terminal-with-presentation %q' "$(printf '%q %s' "$repo/install.sh" "$1")"; }
  jq -n -r --arg add "$(run --add)" --arg remove "$(run --remove)" --arg configure "$(run --configure)" --arg title "Witcher's Tweaks" '
    {
      "setup.witcher": {icon: "󰄛", label: $title, aliases: ["witcher", "tweaks"], description: "Add, remove or configure Witcher'"'"'s Tweaks"},
      "setup.witcher.add": {icon: "", label: "Add", description: "Install tweaks that are not on this machine yet", action: $add},
      "setup.witcher.remove": {icon: "", label: "Remove", description: "Safely take tweaks back out", action: $remove},
      "setup.witcher.configure": {icon: "", label: "Configure", description: "Monitors, border colors and other settings", action: $configure}
    }
    | to_entries[] | "\(.key | tojson): \(.value | tojson),"'
  setup_rows_after_config
}

# The menu lists Omarchy's own rows first, in their file order, and appends
# new ids from the extension file after them, so Witcher's Tweaks would land
# at the bottom of Setup. To sit right under Config, the Setup rows Omarchy
# puts after Config (Direct Boot, Reset Computer) are hidden and re-added
# below it as copies, rebuilt from Omarchy's own menu on every run so they
# keep up with updates. Only plain action rows move; a submenu would leave
# its children behind, so one of those stays where it is.
setup_rows_after_config() {
  local defaults="$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc"
  [[ -f $defaults ]] || return 0
  # The same JSONC clean-up the menu does: drop comment lines, then trailing commas.
  sed '/^[[:space:]]*\/\//d' "$defaults" | perl -0pe 's/,(\s*[}\]])/$1/g' | jq -r '
    [to_entries[] | select(.key | test("^setup\\.[^.]+$"))] as $rows
    | ([$rows[].key] | index("setup.config")) as $at
    | if $at == null then empty else
        $rows[$at + 1:][]
        | select(.value.action != null and .value.action != "")
        | .key as $id
        | "\($id | tojson): {\"when\":\"false\",\"aliases\":[]},",
          "\(("setup.witcher-then-" + ($id | ltrimstr("setup."))) | tojson): \(.value | tojson),"
      end' 2>/dev/null || true
}

# The Setup > Witcher's Tweaks entries live between two marker comments in
# the user's menu extension file, which is otherwise theirs. Rewritten in
# place when they change, so the paths follow the repo.
ensure_menu() {
  if [[ ! -f $menu_file ]]; then
    mkdir -p "$(dirname "$menu_file")"
    if [[ -f $OMARCHY_PATH/config/omarchy/extensions/omarchy-menu.jsonc ]]; then
      cp "$OMARCHY_PATH/config/omarchy/extensions/omarchy-menu.jsonc" "$menu_file"
    else
      printf '{\n}\n' >"$menu_file"
    fi
  fi

  local block current
  block="$menu_begin"$'\n'"$(menu_block)"$'\n'"$menu_end"
  current=$(sed -n "\|^  $menu_begin\$|,\|^  $menu_end\$|p" "$menu_file" | sed 's/^  //')
  if [[ $current == "$block" ]]; then
    echo "ok       Setup > Witcher's Tweaks in the Omarchy menu"
    return 0
  fi

  local tmp="$menu_file.tmp.$stamp"
  # Drop an old block, then put the new one in before the closing brace. The
  # block goes through the environment: awk -v would eat its backslashes.
  sed "\|^  $menu_begin\$|,\|^  $menu_end\$|d" "$menu_file" | BLOCK="$block" awk '
    { lines[NR] = $0 }
    END {
      last = 0
      for (i = NR; i > 0; i--) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { last = i; break }
      for (i = 1; i <= NR; i++) {
        if (i == last) { n = split(ENVIRON["BLOCK"], b, "\n"); for (j = 1; j <= n; j++) print "  " b[j] }
        print lines[i]
      }
    }' >"$tmp"
  mv "$tmp" "$menu_file"
  echo "set      Setup > Witcher's Tweaks in the Omarchy menu"
}

remove_menu() {
  if [[ -f $menu_file ]] && grep -qF "$menu_begin" "$menu_file"; then
    sed -i "\|^  $menu_begin\$|,\|^  $menu_end\$|d" "$menu_file"
    echo "removed  Setup > Witcher's Tweaks from the Omarchy menu"
  else
    echo "ok       Setup > Witcher's Tweaks not in the menu"
  fi
}

# ---------------------------------------------------------------- pickers

tweak_label() {
  local t state label
  t=$(tweak_line "$1")
  label=$(printf '%-14s %s' "$1" "$(field "$t" 3)")
  state=$(tweak_state "$1")
  [[ $state == partial ]] && label+=" (partly installed)"
  echo "$label"
}

# Picks tweaks from a list; prints the chosen names. Nothing preselected.
pick_tweaks() {
  local header="$1"
  shift
  local list=("$@") labels=() name label
  for name in "${list[@]}"; do labels+=("$(tweak_label "$name")"); done

  if command -v gum >/dev/null; then
    gum choose --no-limit --height 20 --header "$header" "${labels[@]}" | while IFS= read -r label; do echo "${label%% *}"; done
  else
    local i answer
    echo "$header" >/dev/tty
    for i in "${!list[@]}"; do
      read -rp "  ${labels[i]}? [y/N] " answer </dev/tty
      [[ $answer =~ ^[Yy] ]] && echo "${list[i]}"
    done
  fi
}

# One question per category, listing that category's tweaks that pass the
# filter (not installed, for adding).
pick_by_category() {
  local verb="$1" category name t list=()
  shift
  for category in "${categories[@]}"; do
    list=()
    for name in "$@"; do
      t=$(tweak_line "$name")
      [[ $(field "$t" 2) == "$category" ]] && list+=("$name")
    done
    (( ${#list[@]} )) || continue
    pick_tweaks "$category: $verb which? Space picks, enter moves on (none is fine)" "${list[@]}"
  done
}

confirm() {
  if command -v gum >/dev/null; then
    gum confirm --default=false "$1"
  else
    local answer
    read -rp "$1 [y/N] " answer </dev/tty
    [[ $answer =~ ^[Yy] ]]
  fi
}

# ---------------------------------------------------------------- main

if ! command -v omarchy >/dev/null; then
  echo "Witcher's Tweaks is for Omarchy (https://omarchy.org); the omarchy command isn't here." >&2
  exit 1
fi

# Tweaks this machine can use, in list order.
names=()
for t in "${tweaks[@]}"; do
  available "$t" && names+=("$(field "$t" 1)")
done

check_names() {
  local want
  for want in "$@"; do
    if [[ " ${names[*]} " != *" $want "* ]]; then
      echo "Unknown or unavailable tweak: $want (see --list)" >&2
      exit 1
    fi
  done
}

need_terminal() {
  if [[ ! -t 0 ]]; then
    echo "No terminal to ask in; pass tweak names (see --list)." >&2
    exit 1
  fi
}

installed_names() {
  local name
  for name in "${names[@]}"; do
    [[ $(tweak_state "$name") == none ]] || echo "$name"
  done
}

mode=add
selected=()
reload_hypr=false
# Set by the steps when a shell plugin comes or goes.
restart_shell=false

case "${1:-}" in
  --monitors)
    exec "$monitor_setup"
    ;;
  --list)
    for category in "${categories[@]}"; do
      for name in "${names[@]}"; do
        t=$(tweak_line "$name")
        [[ $(field "$t" 2) == "$category" ]] && printf '%-14s %-14s %s\n' "$category" "$name" "$(field "$t" 3)"
      done
    done
    exit 0
    ;;
  --status)
    for category in "${categories[@]}"; do
      for name in "${names[@]}"; do
        t=$(tweak_line "$name")
        [[ $(field "$t" 2) == "$category" ]] || continue
        printf '%-14s %-14s %s\n' "$category" "$name" "$(tweak_state "$name" | sed 's/full/installed/; s/none/-/; s/partial/partly installed/')"
      done
    done
    exit 0
    ;;
  --all)
    selected=("${names[@]}")
    ;;
  "" | --add)
    [[ ${1:-} == --add ]] && shift
    if (( $# )); then
      check_names "$@"
      selected=("$@")
    else
      need_terminal
      candidates=()
      for name in "${names[@]}"; do
        [[ $(tweak_state "$name") == full ]] || candidates+=("$name")
      done
      if (( ${#candidates[@]} == 0 )); then
        echo "Every tweak is already installed."
        ensure_menu
        exit 0
      fi
      mapfile -t selected < <(pick_by_category "add" "${candidates[@]}")
    fi
    ;;
  --remove | --uninstall)
    mode=remove
    uninstall=false
    [[ $1 == --uninstall ]] && uninstall=true
    shift
    if $uninstall; then
      mapfile -t selected < <(installed_names)
      if [[ -t 0 ]] && ! confirm "Remove every tweak${selected:+ (${selected[*]})}, the menu entry and the Hyprland loader?"; then
        echo "Nothing removed."
        exit 0
      fi
    elif (( $# )); then
      check_names "$@"
      selected=("$@")
    else
      need_terminal
      mapfile -t candidates < <(installed_names)
      if (( ${#candidates[@]} == 0 )); then
        echo "No tweaks are installed."
        exit 0
      fi
      mapfile -t selected < <(pick_tweaks "Remove which tweaks? Space picks, enter applies" "${candidates[@]}")
      if (( ${#selected[@]} )) && ! confirm "Remove ${selected[*]}? Everything they changed goes back to how it was."; then
        echo "Nothing removed."
        exit 0
      fi
    fi
    ;;
  --configure)
    shift
    mode=configure
    options=()
    for entry in "${configurable[@]}"; do
      owner=$(field "$entry" 4)
      if [[ -z $owner || $(tweak_state "$owner") != none ]]; then options+=("$entry"); fi
    done
    if (( $# )); then
      for entry in "${options[@]}"; do
        [[ $(field "$entry" 1) == "$1" ]] && selected=("$1")
      done
      (( ${#selected[@]} )) || { echo "Nothing to configure for $1 (not installed, or no settings)" >&2; exit 1; }
    else
      need_terminal
      option_labels=()
      for entry in "${options[@]}"; do
        option_labels+=("$(printf '%-14s %s' "$(field "$entry" 1)" "$(field "$entry" 2)")")
      done
      if command -v gum >/dev/null; then
        choice=$(gum choose --header "Configure what?" "${option_labels[@]}") || true
      else
        select choice in "${option_labels[@]}"; do break; done
      fi
      [[ -n ${choice:-} ]] && selected=("${choice%% *}")
    fi
    ;;
  -*)
    echo "Unknown option: $1 (see the top of install.sh)" >&2
    exit 1
    ;;
  *)
    check_names "$@"
    selected=("$@")
    ;;
esac

if (( ${#selected[@]} == 0 )) && [[ ${uninstall:-false} != true ]]; then
  echo "Nothing selected."
  ensure_menu
  exit 0
fi

case $mode in
  add) apply_tweaks "${selected[@]}" ;;
  remove) (( ${#selected[@]} )) && remove_tweaks "${selected[@]}" ;;
  configure)
    for entry in "${configurable[@]}"; do
      [[ $(field "$entry" 1) == "${selected[0]}" ]] && "$(field "$entry" 3)"
    done
    ;;
esac

echo "== menu"
if [[ ${uninstall:-false} == true ]]; then
  tidy_loader
  remove_menu
else
  ensure_menu
fi

# Apply and validate the Hyprland config when running inside a Hyprland session.
if $reload_hypr && command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  errors="$(hyprctl configerrors)"
  if [[ -n "${errors//[[:space:]]/}" ]]; then
    echo "Hyprland config errors:" >&2
    echo "$errors" >&2
    exit 1
  fi
  echo "Hyprland reloaded"
fi

# Restart the Omarchy shell (bar) when a plugin changed and it's running.
# The shell watches the plugins folder and reloads on its own 150 ms after a
# file comes or goes; restarting while that reload is still building plugin
# objects crashes the old process on its way out (a Quickshell teardown race),
# so give it time to settle first.
if $restart_shell && shell_running; then
  sleep 3
  omarchy restart shell >/dev/null
  echo "restarted Omarchy shell"
fi
