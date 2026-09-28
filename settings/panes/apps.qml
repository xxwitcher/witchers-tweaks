import QtQuick
import Quickshell
import "../components"

// Omarchy's default apps (omarchy-default-*); picking one that isn't
// installed lets Omarchy offer to install it.
Column {
  id: pane
  spacing: 22

  Group {
    ChoiceRow {
      label: "Web browser"
      icon: "web-browser-symbolic"; iconColor: "#0a84ff"
      options: [
        { value: "chromium", label: "Chromium" }, { value: "chrome", label: "Google Chrome" }, { value: "brave", label: "Brave" },
        { value: "brave-origin", label: "Brave Origin" }, { value: "edge", label: "Microsoft Edge" }, { value: "firefox", label: "Firefox" },
        { value: "zen", label: "Zen" }
      ]
      current: App.status.browser || ""
      onChosen: function(v) { App.apply(["omarchy-default-browser", v]) }
    }
    ChoiceRow {
      label: "Terminal"
      icon: "utilities-terminal-symbolic"; iconColor: "#1c1c1e"
      options: [{ value: "alacritty", label: "Alacritty" }, { value: "foot", label: "Foot" }, { value: "ghostty", label: "Ghostty" }, { value: "kitty", label: "Kitty" }]
      current: App.status.terminal || ""
      onChosen: function(v) { App.apply(["omarchy-default-terminal", v]) }
    }
    ChoiceRow {
      label: "Editor"
      icon: "document-edit-symbolic"; iconColor: "#30b0c7"
      options: [
        { value: "nvim", label: "Neovim" }, { value: "code", label: "VS Code" }, { value: "cursor", label: "Cursor" },
        { value: "zeditor", label: "Zed" }, { value: "sublime_text", label: "Sublime Text" }, { value: "helix", label: "Helix" },
        { value: "vim", label: "Vim" }, { value: "emacs", label: "Emacs" }
      ]
      current: App.status.editor || ""
      onChosen: function(v) { App.apply(["omarchy-default-editor", v === "zeditor" ? "zed" : v]) }
    }
    ChoiceRow {
      label: "Agent"
      icon: "computer-symbolic"; iconColor: "#bf5af2"
      options: [
        { value: "claude", label: "Claude" }, { value: "codex", label: "Codex" }, { value: "agy", label: "Antigravity" },
        { value: "copilot", label: "Copilot" }, { value: "crush", label: "Crush" }, { value: "grok", label: "Grok" },
        { value: "hermes", label: "Hermes" }, { value: "omp", label: "omp" }, { value: "opencode", label: "OpenCode" },
        { value: "ori", label: "Ori" }, { value: "pi", label: "Pi" }
      ]
      current: App.status.agent || ""
      onChosen: function(v) { App.apply(["omarchy-default-agent", v]) }
    }
  }
}
