# Claude Annotator

Inline annotations for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) responses. Read Claude's output in a Neovim side panel, highlight passages, and attach questions, edits, or notes — all without leaving your terminal.

Annotations are automatically injected as context into your next Claude Code prompt, so Claude sees exactly what you're referring to.

## How it works

```
Claude Code response          Neovim annotator panel
 ┌──────────────────┐         ┌──────────────────────┐
 │ Here is my plan  │         │ Here is my plan      │
 │ for the feature: │  ───►   │ for the feature:     │
 │ 1. Add endpoint  │         │ 1. Add endpoint      │
 │ 2. Update UI     │         │ ──────────────────── │
 │ ...              │         │  ✎ EDIT: use PATCH   │
 └──────────────────┘         │    not POST          │
                              │ 2. Update UI         │
                              └──────────────────────┘
```

1. Claude Code produces a response (or writes a plan)
2. Press **Alt+Shift+A** — a Neovim panel opens with the content
3. Select text, press `<leader>ca`, pick a type, write your annotation
4. Press `<leader>cp` to push — annotations are included in your next prompt
5. Press `<leader>ct` to toggle between the latest **message** and **plan**

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Neovim](https://neovim.io/) >= 0.10
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (Neovim UI component library)
- [Windows Terminal](https://github.com/microsoft/terminal) (for the Alt+Shift+A hotkey panel)
- [whkd](https://github.com/LGUG2Z/whkd) or similar hotkey daemon (optional, for the global hotkey)

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/JBillson/claude-annotator.git
```

### 2. Install the Claude Code plugin

Register the plugin so Claude Code loads the hooks:

```bash
claude plugin add /path/to/claude-annotator
```

Or manually add the plugin path to your Claude Code configuration. The plugin directory is `.claude-plugin/` in this repo — it contains `plugin.json` which tells Claude Code about the hooks.

### 3. Install the Neovim plugin

Add the plugin to your Neovim package manager. The plugin depends on [nui.nvim](https://github.com/MunifTanjim/nui.nvim).

**lazy.nvim:**

```lua
{
  "JBillson/claude-annotator",
  dependencies = { "MunifTanjim/nui.nvim" },
  config = function()
    require("claude-annotator").setup()
  end,
  -- Only load in the annotator panel
  cmd = { "ClaudeAnnotatorOpen", "ClaudeAnnotatorPlan" },
}
```

The Neovim plugin source lives in `nvim-plugin/lua/claude-annotator/`. If your package manager doesn't resolve the subdirectory automatically, you may need to add `nvim-plugin/` to your runtimepath:

```lua
vim.opt.rtp:append("/path/to/claude-annotator/nvim-plugin")
```

### 4. Set up the global hotkey (optional)

The `scripts/toggle-panel.ps1` PowerShell script opens (or closes) the annotator as a Windows Terminal side pane. Bind it to a hotkey with [whkd](https://github.com/LGUG2Z/whkd) or another hotkey daemon.

**whkd example** (`~/.config/whkd/whkdrc`):

```
alt + shift + a : powershell -WindowStyle Hidden -File "C:/path/to/claude-annotator/scripts/toggle-panel.ps1"
```

This opens Neovim in a 35%-width vertical split pane running `:ClaudeAnnotatorOpen`.

## Usage

### Opening the annotator

| Method | Description |
|--------|-------------|
| **Alt+Shift+A** | Global hotkey (requires whkd setup above) |
| `:ClaudeAnnotatorOpen` | Opens whichever is newer — the last message or the last plan |
| `:ClaudeAnnotatorPlan` | Opens the latest plan file directly |

On open, the annotator compares the timestamp of the latest Claude response against the latest plan file in `~/.claude/plans/` and shows whichever is newer.

### Keybindings

All keybindings use `<leader>` (default: `\`).

| Mode | Key | Action |
|------|-----|--------|
| Visual | `<leader>ca` | **Annotate** — select text, pick a type, write your annotation |
| Normal | `<leader>cp` | **Push** — queue all pending annotations for the next prompt |
| Normal | `<leader>ct` | **Toggle** — switch between message view and plan view |
| Normal | `<leader>cl` | **List** — toggle the annotation list sidebar |

### Annotation types

| Type | Key | Purpose |
|------|-----|---------|
| **Edit** | `e` | Request a change to the highlighted code/text |
| **Question** | `q` | Ask Claude about the highlighted passage |
| **Note** | `n` | Add context for Claude to keep in mind |

### Workflow

1. Claude Code finishes a response or writes a plan
2. Open the annotator (`Alt+Shift+A` or `:ClaudeAnnotatorOpen`)
3. Read through the content — use `<leader>ct` to toggle between message and plan
4. Select text in visual mode, press `<leader>ca`
5. Choose annotation type: `e` (edit), `q` (question), or `n` (note)
6. Type your annotation content and press Enter
7. Repeat for additional annotations
8. Press `<leader>cp` to push all pending annotations
9. Go back to Claude Code and submit your next prompt — annotations are included automatically

### Auto-reload

The annotator watches for changes in real time:

- When Claude produces a new response, the buffer updates automatically (in message view)
- When a plan file is created or updated, the buffer updates automatically (in plan view)

## Architecture

```
┌─────────────┐     on-stop.js      ┌──────────────────────────────────┐
│ Claude Code  │ ──────────────────► │ ~/.claude-annotator/             │
│              │                     │   current-response.json          │
│              │  on-prompt-submit.js│   pending-annotations.json       │
│              │ ◄────────────────── │                                  │
└─────────────┘                     └──────────┬───────────────────────┘
                                               │ file watcher
                                    ┌──────────▼───────────────────────┐
                                    │ Neovim plugin                    │
                                    │   loader.lua   — read content    │
                                    │   watcher.lua  — watch for       │
                                    │                  changes         │
                                    │   annotate.lua — create          │
                                    │                  annotations     │
                                    │   display.lua  — render extmarks │
                                    │   push.lua     — write pending   │
                                    │                  annotations     │
                                    └──────────────────────────────────┘

                                    ┌──────────────────────────────────┐
                                    │ ~/.claude/plans/*.md             │
                                    │   (also watched for plan view)   │
                                    └──────────────────────────────────┘
```

**Hooks** (Node.js, run by Claude Code):
- `on-stop.js` — captures the latest assistant response to `current-response.json`
- `on-prompt-submit.js` — reads `pending-annotations.json` and injects annotations as context

**Neovim plugin** (Lua):
- Renders content in a read-only buffer with Markdown syntax highlighting
- Annotations displayed as virtual lines (extmarks) below the anchored text
- File-based IPC — no API credentials needed in the plugin

## Customization

### Colors

The plugin uses [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) colors by default. Override the highlight groups in your Neovim config:

```lua
vim.api.nvim_set_hl(0, "ClaudeAnnotateEdit", { fg = "#f38ba8", bold = true })
vim.api.nvim_set_hl(0, "ClaudeAnnotateQuestion", { fg = "#89b4fa", bold = true })
vim.api.nvim_set_hl(0, "ClaudeAnnotateNote", { fg = "#a6adc8", bold = true })
```

### Panel size

Edit `scripts/toggle-panel.ps1` to change the panel width (default 35%):

```powershell
wt -w 0 sp -V --size 0.35 --title "$PanelTitle" -- nvim -c "ClaudeAnnotatorOpen"
```

## Limitations

- Windows-only for the global hotkey panel (the Neovim plugin itself is cross-platform)
- Annotations are per-session — they reset when a new response arrives
- Requires [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for the annotation input popups

## License

MIT
