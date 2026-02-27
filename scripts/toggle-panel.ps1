# Toggle the Claude Annotator panel in Windows Terminal as a side pane.
# Called by whkd hotkey (alt + shift + a).

$PanelTitle = "Claude Annotator"

# Check if a process with the panel window title is running
$existing = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -eq $PanelTitle
}

if ($existing) {
    # Close the panel
    $existing | ForEach-Object { $_.CloseMainWindow() | Out-Null }
} else {
    # Open as a vertical split pane in the current Windows Terminal window
    wt -w 0 sp -V --size 0.50 --title "$PanelTitle" -- nvim -c "ClaudeAnnotatorOpen"
}
