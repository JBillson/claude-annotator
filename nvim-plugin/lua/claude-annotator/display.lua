local M = {}

local init = require("claude-annotator")

local type_icons = {
  edit = "",
  question = "",
  note = "",
}

local type_hl = {
  edit = "ClaudeAnnotateEdit",
  question = "ClaudeAnnotateQuestion",
  note = "ClaudeAnnotateNote",
}

local type_hl_dim = {
  edit = "ClaudeAnnotateEditDim",
  question = "ClaudeAnnotateQuestionDim",
  note = "ClaudeAnnotateNoteDim",
}

local type_border_hl = {
  edit = "ClaudeAnnotateBorderEdit",
  question = "ClaudeAnnotateBorderQuestion",
  note = "ClaudeAnnotateBorderNote",
}

--- Render all annotations as extmarks with virtual lines
---@param bufnr number
function M.render(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, init.ns, 0, -1)

  local annotations = vim.b[bufnr].annotations or {}

  for _, ann in ipairs(annotations) do
    local line = ann.anchor_end_line
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    -- Clamp to buffer bounds
    if line >= line_count then
      line = line_count - 1
    end
    if line < 0 then
      line = 0
    end

    local is_sent = ann.status == "sent"
    local icon = type_icons[ann.type] or ""
    local hl = is_sent and (type_hl_dim[ann.type] or "Comment") or (type_hl[ann.type] or "Comment")
    local border_hl = type_border_hl[ann.type] or "Comment"

    -- Build virtual lines
    local label = string.upper(ann.type)
    local prefix = icon .. " " .. label .. ": "
    local status_text = is_sent and " [sent]" or ""

    local virt_lines = {
      -- Border line
      { { "  " .. string.rep("─", 50), border_hl } },
      -- Annotation content
      { { "  " .. prefix, hl }, { ann.content .. status_text, hl } },
    }

    -- Wrap long content across multiple virtual lines
    local max_width = 70
    local full_text = prefix .. ann.content .. status_text
    if #full_text > max_width then
      virt_lines = {
        { { "  " .. string.rep("─", 50), border_hl } },
        { { "  " .. icon .. " " .. label .. ":", hl } },
      }
      -- Word-wrap the content
      local remaining = ann.content .. status_text
      while #remaining > 0 do
        local chunk = string.sub(remaining, 1, max_width - 4)
        remaining = string.sub(remaining, max_width - 3)
        virt_lines[#virt_lines + 1] = { { "    " .. chunk, hl } }
      end
    end

    vim.api.nvim_buf_set_extmark(bufnr, init.ns, line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
    })
  end
end

--- State for the annotation list split
local list_bufnr = nil
local list_winnr = nil

--- Toggle the annotation list sidebar
function M.toggle_list()
  -- If list window exists and is valid, close it
  if list_winnr and vim.api.nvim_win_is_valid(list_winnr) then
    vim.api.nvim_win_close(list_winnr, true)
    list_winnr = nil
    return
  end

  local source_bufnr = vim.api.nvim_get_current_buf()
  local annotations = vim.b[source_bufnr].annotations or {}

  -- Create or reuse buffer
  if not list_bufnr or not vim.api.nvim_buf_is_valid(list_bufnr) then
    list_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[list_bufnr].buftype = "nofile"
    vim.bo[list_bufnr].swapfile = false
    vim.bo[list_bufnr].filetype = "claude-annotation-list"
  end

  -- Build list content
  local lines = { "Annotations (" .. #annotations .. ")", string.rep("─", 40) }
  for i, ann in ipairs(annotations) do
    local icon = type_icons[ann.type] or ""
    local status = ann.status == "sent" and " [sent]" or " [pending]"
    local preview = string.sub(ann.content, 1, 35)
    if #ann.content > 35 then
      preview = preview .. "..."
    end
    lines[#lines + 1] = string.format("%d. %s %s: %s%s", i, icon, ann.type, preview, status)
  end

  if #annotations == 0 then
    lines[#lines + 1] = "  (no annotations yet)"
  end

  vim.bo[list_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(list_bufnr, 0, -1, false, lines)
  vim.bo[list_bufnr].modifiable = false

  -- Open in a vertical split on the right
  vim.cmd("botright vsplit")
  list_winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(list_winnr, list_bufnr)
  vim.api.nvim_win_set_width(list_winnr, 45)

  -- Return focus to the source window
  vim.cmd("wincmd p")
end

return M
