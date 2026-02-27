local M = {}

local init = require("claude-annotator")
local display = require("claude-annotator.display")

--- Push all pending annotations to the IPC file
function M.push_annotations()
  local bufnr = vim.api.nvim_get_current_buf()
  local annotations = vim.b[bufnr].annotations or {}

  -- Filter to pending only
  local pending = {}
  for _, ann in ipairs(annotations) do
    if ann.status == "pending" then
      pending[#pending + 1] = {
        id = ann.id,
        message_id = ann.message_id,
        anchor_start = ann.anchor_start_line,
        anchor_end = ann.anchor_end_line,
        anchor_text = ann.anchor_text,
        content = ann.content,
        type = ann.type,
      }
    end
  end

  if #pending == 0 then
    vim.notify("No pending annotations to push", vim.log.levels.WARN)
    return
  end

  -- Ensure IPC directory exists
  vim.fn.mkdir(init.ipc_dir, "p")

  -- Serialize to JSON
  local json = vim.json.encode(pending)
  local path = init.ipc_dir .. "/pending-annotations.json"

  local f = io.open(path, "w")
  if not f then
    vim.notify("Failed to write " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(json)
  f:close()

  -- Mark pushed annotations as sent
  local updated = {}
  for _, ann in ipairs(annotations) do
    local copy = vim.deepcopy(ann)
    if copy.status == "pending" then
      copy.status = "sent"
    end
    updated[#updated + 1] = copy
  end
  vim.b[bufnr].annotations = updated

  -- Re-render extmarks
  display.render(bufnr)

  vim.notify(
    #pending .. " annotation(s) queued — included in your next Claude Code prompt",
    vim.log.levels.INFO
  )
end

return M
