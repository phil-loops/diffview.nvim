-- Stack Drift Detection Module
-- Detects files with "drift" (code removed downstream in stacked PRs)

local M = {}

-- Cache for drift data
local cache = {
  data = nil,
  last_updated = 0,
  toplevel = nil,
}

-- Get drift data from the stack CLI
---@return table<string, boolean> Map of filepath -> true for drifted files
function M.get_drift_files()
  local now = vim.loop.now()

  -- Refresh cache every 30 seconds or if toplevel changed
  local git_toplevel = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  if vim.v.shell_error ~= 0 then
    return {}
  end

  if cache.data and cache.toplevel == git_toplevel and (now - cache.last_updated) < 30000 then
    return cache.data
  end

  -- Check if this is a stacked repo
  local stack_file = vim.fn.glob(git_toplevel .. '/.stack')
  if stack_file == '' then
    -- Also check ~/.local/share/stack/<repo>/stack
    local repo_name = vim.fn.fnamemodify(git_toplevel, ':t')
    stack_file = vim.fn.expand('~/.local/share/stack/' .. repo_name .. '/stack')
    if vim.fn.filereadable(stack_file) ~= 1 then
      cache.data = {}
      cache.toplevel = git_toplevel
      cache.last_updated = now
      return {}
    end
  end

  -- Run stack info -d to get drift info
  local STACK_CMD = 'node --no-warnings --experimental-strip-types ~/.dotfiles/scripts/stack/index.ts'
  local output = vim.fn.systemlist(STACK_CMD .. ' info -d 2>/dev/null')

  local drift_files = {}
  local in_drift_section = false

  for _, line in ipairs(output) do
    if line:match('^Drifted files') then
      in_drift_section = true
    elseif in_drift_section then
      -- Parse lines like: "  queries/goal-window.ts"
      local filepath = line:match('^%s%s([^%s].+)$')
      if filepath and not filepath:match('^added:') then
        drift_files[filepath] = true
      end
    end
  end

  cache.data = drift_files
  cache.toplevel = git_toplevel
  cache.last_updated = now

  return drift_files
end

-- Invalidate the cache
function M.invalidate()
  cache.data = nil
  cache.last_updated = 0
end

-- Check if a specific file has drift
---@param filepath string The file path relative to repo root
---@return boolean
function M.has_drift(filepath)
  local drift_files = M.get_drift_files()

  -- Direct match
  if drift_files[filepath] then
    return true
  end

  -- Try matching by basename (in case paths differ slightly)
  local basename = vim.fn.fnamemodify(filepath, ':t')
  for drifted_path, _ in pairs(drift_files) do
    if vim.fn.fnamemodify(drifted_path, ':t') == basename then
      return true
    end
  end

  return false
end

return M
