local M = {}

local ns = vim.api.nvim_create_namespace("claude-annotator")

M.ns = ns
M.ipc_dir = (os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/.claude-annotator"

function M.setup()
  local loader = require("claude-annotator.loader")
  local annotate = require("claude-annotator.annotate")
  local push = require("claude-annotator.push")
  local display = require("claude-annotator.display")

  -- Register filetype and map it to the markdown treesitter parser
  vim.filetype.add({
    pattern = {
      ["claude%-response"] = "claude-response",
    },
  })
  vim.treesitter.language.register("markdown", "claude-response")

  -- Highlight groups
  local function set_highlights()
    vim.api.nvim_set_hl(0, "ClaudeAnnotateQuestion", { fg = "#89b4fa", bold = true })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateNote", { fg = "#a6adc8", bold = true })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateQuestionDim", { fg = "#89b4fa", bold = false })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateNoteDim", { fg = "#a6adc8", bold = false })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateBorderQuestion", { fg = "#89b4fa" })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateBorderNote", { fg = "#a6adc8" })
    vim.api.nvim_set_hl(0, "ClaudeAnnotateLabel", { fg = "#cdd6f4", bold = true })
  end
  set_highlights()

  -- User command — open with latest message
  vim.api.nvim_create_user_command("ClaudeAnnotatorOpen", function()
    local bufnr = loader.load_latest()
    if bufnr then
      local watcher = require("claude-annotator.watcher")
      watcher.start(bufnr)
    end
  end, { desc = "Open Claude Annotator with latest response" })

  -- User command — open with latest plan
  vim.api.nvim_create_user_command("ClaudeAnnotatorPlan", function()
    local bufnr = loader.load_latest_plan()
    if bufnr then
      local watcher = require("claude-annotator.watcher")
      watcher.start(bufnr)
    end
  end, { desc = "Open Claude Annotator with latest plan" })

  -- Keymaps (visual mode) — annotate selection
  vim.keymap.set("v", "<leader>ca", function()
    annotate.create_from_visual()
  end, { desc = "Claude: Annotate selection" })

  -- Keymaps (normal mode) — edit annotation at cursor
  vim.keymap.set("n", "<leader>ce", function()
    annotate.edit_at_cursor()
  end, { desc = "Claude: Edit annotation at cursor" })

  -- Keymaps (normal mode) — push annotations
  vim.keymap.set("n", "<leader>cp", function()
    push.push_annotations()
  end, { desc = "Claude: Push annotations" })

  -- Keymaps (normal mode) — toggle annotation list
  vim.keymap.set("n", "<leader>cl", function()
    display.toggle_list()
  end, { desc = "Claude: Toggle annotation list" })

  -- Keymaps (normal mode) — toggle between message and plan view
  vim.keymap.set("n", "<leader>ct", function()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.b[bufnr].claude_view_mode then
      loader.toggle_view(bufnr)
    else
      vim.notify("Not in a Claude Annotator buffer", vim.log.levels.WARN)
    end
  end, { desc = "Claude: Toggle message/plan view" })

  -- Autocmd for claude-response filetype
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "claude-response",
    callback = function(args)
      local buf = args.buf
      vim.bo[buf].modifiable = false
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].swapfile = false
      vim.wo.wrap = true
      vim.wo.linebreak = true
      vim.wo.conceallevel = 2
      -- Use markdown treesitter
      vim.treesitter.start(buf, "markdown")
    end,
  })
end

return M
