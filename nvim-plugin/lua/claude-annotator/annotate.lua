local M = {}

local display = require("claude-annotator.display")
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event

local type_labels = {
  e = "edit",
  q = "question",
  n = "note",
}

local type_display = {
  edit = "Edit",
  question = "Question",
  note = "Note",
}

--- Generate a simple UUID-like string
local function uuid()
  local random = math.random
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 0xf) or random(8, 0xb)
    return string.format("%x", v)
  end)
end

--- Open the type selector popup, then the annotation input
function M.create_from_visual()
  -- Capture visual selection before leaving visual mode
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Exit visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  -- Wait a tick for marks to settle
  vim.schedule(function()
    -- Re-read marks after exiting visual mode
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")

    local bufnr = vim.api.nvim_get_current_buf()
    local start_line = start_pos[2] - 1 -- 0-indexed
    local end_line = end_pos[2] - 1

    -- Extract selected text
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    if #lines == 0 then
      vim.notify("No text selected", vim.log.levels.WARN)
      return
    end

    -- Trim to visual columns for partial line selections
    local start_col = start_pos[3] - 1
    local end_col = end_pos[3]
    if #lines == 1 then
      lines[1] = string.sub(lines[1], start_col + 1, end_col)
    else
      lines[1] = string.sub(lines[1], start_col + 1)
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end

    local anchor_text = table.concat(lines, "\n")

    -- Show type selector
    M._show_type_selector(bufnr, start_line, end_line, anchor_text)
  end)
end

--- Display the type selector popup
---@param bufnr number
---@param start_line number 0-indexed
---@param end_line number 0-indexed
---@param anchor_text string
function M._show_type_selector(bufnr, start_line, end_line, anchor_text)
  local popup = Input({
    position = "50%",
    size = { width = 40 },
    border = {
      style = "rounded",
      text = {
        top = " [e]dit  [q]uestion  [n]ote ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = "",
    on_submit = function() end,
  })

  popup:mount()

  -- Single keypress to select type
  for key, ann_type in pairs(type_labels) do
    popup:map("n", key, function()
      popup:unmount()
      M._show_content_input(bufnr, start_line, end_line, anchor_text, ann_type)
    end, { noremap = true })
    popup:map("i", key, function()
      popup:unmount()
      M._show_content_input(bufnr, start_line, end_line, anchor_text, ann_type)
    end, { noremap = true })
  end

  -- Cancel
  popup:map("n", "<Esc>", function()
    popup:unmount()
  end, { noremap = true })

  popup:on(event.BufLeave, function()
    popup:unmount()
  end)
end

--- Display the content input popup
---@param bufnr number
---@param start_line number 0-indexed
---@param end_line number 0-indexed
---@param anchor_text string
---@param ann_type string
function M._show_content_input(bufnr, start_line, end_line, anchor_text, ann_type)
  local label = type_display[ann_type] or ann_type

  local input = Input({
    position = "50%",
    size = { width = 60 },
    border = {
      style = "rounded",
      text = {
        top = " " .. label .. " annotation ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = "> ",
    on_submit = function(value)
      if not value or value == "" then
        return
      end

      local annotation = {
        id = uuid(),
        message_id = vim.b[bufnr].claude_message_id,
        anchor_start_line = start_line,
        anchor_end_line = end_line,
        anchor_text = anchor_text,
        content = value,
        type = ann_type,
        status = "pending",
      }

      -- Store annotation
      local annotations = vim.b[bufnr].annotations or {}
      annotations[#annotations + 1] = annotation
      vim.b[bufnr].annotations = annotations

      -- Render extmarks
      display.render(bufnr)

      vim.notify(label .. " annotation added", vim.log.levels.INFO)
    end,
  })

  input:mount()

  -- Start in insert mode
  vim.cmd("startinsert")

  -- Cancel
  input:map("n", "<Esc>", function()
    input:unmount()
  end, { noremap = true })

  input:on(event.BufLeave, function()
    input:unmount()
  end)
end

return M
