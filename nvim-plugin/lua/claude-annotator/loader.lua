local M = {}

local init = require("claude-annotator")

local plans_dir = (os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/.claude/plans"

--- Read the current-response.json IPC file
---@return table|nil parsed JSON table or nil
local function read_ipc_response()
  local path = init.ipc_dir .. "/current-response.json"
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local raw = f:read("*a")
  f:close()
  if not raw or raw == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not data or not data.content then
    return nil
  end
  return data
end

--- Scan Claude transcript files for the most recent assistant message
---@return string|nil content
local function read_transcript_fallback()
  local claude_dir = (os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/.claude/projects"
  local projects = vim.fn.glob(claude_dir .. "/*", false, true)

  local newest_file = nil
  local newest_mtime = 0

  for _, project_dir in ipairs(projects) do
    local jsonl_files = vim.fn.glob(project_dir .. "/*.jsonl", false, true)
    for _, file in ipairs(jsonl_files) do
      local stat = vim.uv.fs_stat(file)
      if stat and stat.mtime.sec > newest_mtime then
        newest_mtime = stat.mtime.sec
        newest_file = file
      end
    end
  end

  if not newest_file then
    return nil
  end

  -- Read file and walk backwards for last assistant text
  local lines = {}
  for line in io.lines(newest_file) do
    lines[#lines + 1] = line
  end

  for i = #lines, 1, -1 do
    local ok, entry = pcall(vim.json.decode, lines[i])
    if ok and entry and entry.type == "assistant" then
      -- Extract text content from message
      if type(entry.message) == "table" and type(entry.message.content) == "table" then
        local parts = {}
        for _, block in ipairs(entry.message.content) do
          if block.type == "text" and block.text then
            parts[#parts + 1] = block.text
          end
        end
        if #parts > 0 then
          return table.concat(parts, "\n\n")
        end
      elseif type(entry.message) == "table" and type(entry.message.content) == "string" then
        return entry.message.content
      end
    end
  end

  return nil
end

--- Find the latest plan file in ~/.claude/plans/
---@return string|nil content, string|nil filepath, number|nil mtime
local function read_latest_plan()
  local plan_files = vim.fn.glob(plans_dir .. "/*.md", false, true)
  if #plan_files == 0 then
    return nil, nil, nil
  end

  local newest_file = nil
  local newest_mtime = 0

  for _, file in ipairs(plan_files) do
    local stat = vim.uv.fs_stat(file)
    if stat and stat.mtime.sec > newest_mtime then
      newest_mtime = stat.mtime.sec
      newest_file = file
    end
  end

  if not newest_file then
    return nil, nil, nil
  end

  local f = io.open(newest_file, "r")
  if not f then
    return nil, nil, nil
  end
  local content = f:read("*a")
  f:close()

  if not content or content == "" then
    return nil, nil, nil
  end

  return content, newest_file, newest_mtime
end

--- Set buffer content and metadata
---@param bufnr number
---@param content string
---@param view_mode "message"|"plan"
---@param meta table|nil extra metadata
local function set_buffer(bufnr, content, view_mode, meta)
  meta = meta or {}
  local lines = vim.split(content, "\n")

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  vim.b[bufnr].claude_view_mode = view_mode
  vim.b[bufnr].claude_message_id = meta.message_id
  vim.b[bufnr].claude_plan_path = meta.plan_path
  vim.b[bufnr].annotations = {}

  -- Clear extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, init.ns, 0, -1)
end

--- Load whichever is newest (message or plan) into a scratch buffer
---@return number|nil bufnr
function M.load_latest()
  -- Gather message
  local msg_data = read_ipc_response()
  local msg_content = nil
  local msg_mtime = 0
  local message_id = nil

  if msg_data then
    msg_content = msg_data.content
    message_id = msg_data.message_id
    -- Get mtime from the IPC file
    local ipc_path = init.ipc_dir .. "/current-response.json"
    local stat = vim.uv.fs_stat(ipc_path)
    if stat then
      msg_mtime = stat.mtime.sec
    end
  else
    msg_content = read_transcript_fallback()
  end

  -- Gather plan
  local plan_content, plan_path, plan_mtime = read_latest_plan()
  plan_mtime = plan_mtime or 0

  -- Pick whichever is newer, preferring plan when equal
  local use_plan = plan_content and (plan_mtime >= msg_mtime)
  local content, view_mode, meta

  if use_plan then
    content = plan_content
    view_mode = "plan"
    meta = { plan_path = plan_path }
  elseif msg_content then
    content = msg_content
    view_mode = "message"
    meta = { message_id = message_id }
  end

  if not content then
    vim.notify("No Claude response or plan found", vim.log.levels.WARN)
    return nil
  end

  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "claude-response"

  set_buffer(bufnr, content, view_mode, meta)

  vim.api.nvim_set_current_buf(bufnr)

  if view_mode == "plan" then
    local name = vim.fn.fnamemodify(plan_path, ":t")
    vim.notify("Plan loaded: " .. name .. "  (<leader>ct to toggle)", vim.log.levels.INFO)
  else
    vim.notify("Claude response loaded  (<leader>ct to toggle)", vim.log.levels.INFO)
  end

  return bufnr
end

--- Load the latest plan file into a scratch buffer
---@return number|nil bufnr
function M.load_latest_plan()
  local content, filepath = read_latest_plan()

  if not content then
    vim.notify("No Claude plan found", vim.log.levels.WARN)
    return nil
  end

  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "claude-response"

  set_buffer(bufnr, content, "plan", { plan_path = filepath })

  vim.api.nvim_set_current_buf(bufnr)

  local name = vim.fn.fnamemodify(filepath, ":t")
  vim.notify("Plan loaded: " .. name, vim.log.levels.INFO)

  return bufnr
end

--- Toggle the current buffer between message and plan views
---@param bufnr number
function M.toggle_view(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local current_mode = vim.b[bufnr].claude_view_mode or "message"

  if current_mode == "message" then
    -- Switch to plan
    local content, filepath = read_latest_plan()
    if not content then
      vim.notify("No Claude plan found", vim.log.levels.WARN)
      return
    end
    set_buffer(bufnr, content, "plan", { plan_path = filepath })
    local name = vim.fn.fnamemodify(filepath, ":t")
    vim.notify("Switched to plan: " .. name, vim.log.levels.INFO)
  else
    -- Switch to message
    local data = read_ipc_response()
    local content = nil
    local message_id = nil

    if data then
      content = data.content
      message_id = data.message_id
    else
      content = read_transcript_fallback()
    end

    if not content then
      vim.notify("No Claude response found", vim.log.levels.WARN)
      return
    end
    set_buffer(bufnr, content, "message", { message_id = message_id })
    vim.notify("Switched to message", vim.log.levels.INFO)
  end
end

--- Reload an existing buffer with fresh content (respects current view mode)
---@param bufnr number
function M.reload(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local current_mode = vim.b[bufnr].claude_view_mode or "message"

  if current_mode == "plan" then
    local content, filepath = read_latest_plan()
    if not content then
      return
    end
    set_buffer(bufnr, content, "plan", { plan_path = filepath })
    vim.notify("Plan updated", vim.log.levels.INFO)
  else
    local data = read_ipc_response()
    if not data then
      return
    end
    set_buffer(bufnr, data.content, "message", { message_id = data.message_id })
    vim.notify("Claude response updated", vim.log.levels.INFO)
  end
end

return M
