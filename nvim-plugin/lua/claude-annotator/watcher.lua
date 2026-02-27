local M = {}

local init = require("claude-annotator")
local loader = require("claude-annotator.loader")

local handles = {}

local plans_dir = (os.getenv("HOME") or os.getenv("USERPROFILE")) .. "/.claude/plans"

--- Create a debounced fs watcher on a path
---@param path string
---@param bufnr number
---@return userdata|nil handle
local function watch_path(path, bufnr)
  local h = vim.uv.new_fs_event()
  if not h then
    return nil
  end

  local debounce_timer = nil

  h:start(path, {}, function(err, filename, events)
    if err then
      return
    end

    if debounce_timer then
      debounce_timer:stop()
    end

    debounce_timer = vim.uv.new_timer()
    debounce_timer:start(200, 0, function()
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          loader.reload(bufnr)
        else
          M.stop()
        end
      end)
    end)
  end)

  return h
end

--- Start watching for changes (both IPC response and plans directory)
---@param bufnr number
function M.start(bufnr)
  M.stop()

  -- Watch IPC response file/dir
  local ipc_path = init.ipc_dir .. "/current-response.json"
  local stat = vim.uv.fs_stat(ipc_path)
  if not stat then
    local dir_stat = vim.uv.fs_stat(init.ipc_dir)
    if not dir_stat then
      vim.fn.mkdir(init.ipc_dir, "p")
    end
    ipc_path = init.ipc_dir
  end

  local ipc_handle = watch_path(ipc_path, bufnr)
  if ipc_handle then
    handles[#handles + 1] = ipc_handle
  end

  -- Watch plans directory
  local plans_stat = vim.uv.fs_stat(plans_dir)
  if plans_stat then
    local plan_handle = watch_path(plans_dir, bufnr)
    if plan_handle then
      handles[#handles + 1] = plan_handle
    end
  end
end

--- Stop all file watchers
function M.stop()
  for _, h in ipairs(handles) do
    h:stop()
    h:close()
  end
  handles = {}
end

return M
