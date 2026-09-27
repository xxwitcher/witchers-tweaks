# Agent Terminal (witcher.agents)

A clone of Omarchy's `omarchy.agents` bar widget. The popup keeps a compact
header (the agent's mark, name and plan, then the session and weekly limits
side by side) and puts a real terminal underneath, running your default agent
exactly like the agent console does: `omarchy-agent --inline`. So it's the
agent's own interface, with every slash command and interactive feature, for
whichever agent is the default, including its auto-approve flag and its
Omarchy skills and rules.

- The terminal is a `QMLTermWidget` (package `qmltermwidget`). It lives as
  long as the shell, so closing the popup keeps the session. Restart starts a
  fresh one (Start, if the agent exited).
- Every key goes to the agent, Esc and Tab included. Close the popup by
  clicking the bar icon or outside it.
- `bin/terminal-colors` writes `~/.local/state/witcher-agents/Omarchy.colorscheme`
  from the current theme whenever the popup opens. The library only reads
  schemes from its own folder, so the `agentchat` module links that file into
  `/usr/lib/qt6/qml/QMLTermWidget/color-schemes/`. New colors apply after
  `omarchy restart shell`.
- Usage data comes from copies of the stock `Main.qml` / `Agent.qml`.

IPC: `omarchy-shell witcher.agents <open|close|toggle|restart|refresh|next>`.
