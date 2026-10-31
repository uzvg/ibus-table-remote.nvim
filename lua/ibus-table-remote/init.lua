-- ibus-table-remote.nvim
-- Switch ibus-table input mode (Table/Direct) around Neovim modes via gsettings.

local M = {}

local state = {
  saved = nil, -- input mode to restore when leaving normal/visual mode
  active = false, -- whether we have switched to Direct mode
  schema = nil, -- resolved gsettings schema string
}

local defaults = {
  -- ibus-table schema name, e.g. "zhengma". When nil, auto-detect from
  -- `ibus engine` (expects output like "table:zhengma").
  schema = nil,
  -- gsettings value for Direct/ASCII mode. Table mode is 1.
  direct_mode = 0,
  -- Show warnings/errors through vim.notify.
  notify = true,
}

local config = vim.deepcopy(defaults)

local notified = {}

local function notify(message, level)
  if not config.notify then
    return
  end
  local key = message:gsub("%d+", "N")
  if notified[key] then
    return
  end
  notified[key] = true
  vim.notify("ibus-table-remote: " .. message, level or vim.log.levels.WARN)
end

-- `vim.system()` is available in supported Neovim versions and avoids the
-- global, mutable `vim.v.shell_error` used by vim.fn.system().
local function run(command)
  local result = vim.system(command, { text = true }):wait()
  return result.code == 0, result.stdout or "", result.stderr or ""
end

-- Turn the configured schema into a full gsettings schema string.
-- Accepts "zhengma", "table:zhengma", or a full
-- "org.freedesktop.ibus.engine.table:/.../zhengma/" string.
local function resolve_schema()
  if state.schema then
    return state.schema
  end

  local schema = config.schema
  if schema == nil or schema == "" then
    local ok, output = run({ "ibus", "engine" })
    if not ok then
      return nil
    end
    schema = vim.trim(output):match("^table:(.+)$")
    if not schema then
      return nil
    end
  end

  schema = vim.trim(schema)
  if schema:find(":/", 1, true) then
    if not schema:match("/$") then
      schema = schema .. "/"
    end
    state.schema = schema
  else
    schema = schema:gsub("^table:", "")
    if not schema:match("/$") then
      schema = schema .. "/"
    end
    state.schema = "org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/"
      .. schema
  end

  return state.schema
end

local function get_mode()
  local schema = resolve_schema()
  if not schema then
    notify("cannot determine ibus-table schema, set `schema` in setup()", vim.log.levels.ERROR)
    return nil
  end

  local ok, output, error = run({ "gsettings", "get", schema, "inputmode" })
  if not ok then
    notify("failed to read input mode: " .. vim.trim(error ~= "" and error or output), vim.log.levels.ERROR)
    return nil
  end

  local value = tonumber(output:match("(%d+)%s*$"))
  if value == nil then
    notify("unexpected gsettings output: " .. vim.trim(output), vim.log.levels.ERROR)
  end
  return value
end

local function set_mode(value)
  local schema = resolve_schema()
  if not schema then
    notify("cannot determine ibus-table schema, set `schema` in setup()", vim.log.levels.ERROR)
    return false
  end

  local ok, output, error = run({ "gsettings", "set", schema, "inputmode", tostring(value) })
  if not ok then
    notify("failed to set input mode to " .. value .. ": " .. vim.trim(error ~= "" and error or output), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Normal, visual, select and operator-pending modes: no text input needed.
local ascii_modes = {
  n = true,
  v = true,
  V = true,
  ["\22"] = true, -- CTRL-V (blockwise visual)
  s = true,
  S = true,
  ["\19"] = true, -- CTRL-S (blockwise select)
  o = true,
}

-- Modes in which the user types text, so ibus-table should be in Table mode.
local insert_modes = {
  i = true,
  R = true,
  t = true,
}

local function is_ascii_mode(mode)
  return ascii_modes[mode:sub(1, 1)] == true
end

local function is_insert_mode(mode)
  return insert_modes[mode:sub(1, 1)] == true
end

local function enter_ascii_mode()
  if state.active then
    return
  end

  local current = get_mode()
  if current == nil then
    return
  end

  state.saved = current
  state.active = true

  if current ~= config.direct_mode and not set_mode(config.direct_mode) then
    state.active = false
    state.saved = nil
  end
end

local function leave_ascii_mode()
  if not state.active then
    return
  end

  local saved = state.saved
  state.active = false
  state.saved = nil

  if saved ~= nil and saved ~= config.direct_mode then
    set_mode(saved)
  end
end

local function on_mode_changed(new_mode)
  new_mode = new_mode or vim.v.event.new_mode
  if not new_mode then
    return
  end
  if is_ascii_mode(new_mode) then
    enter_ascii_mode()
  elseif is_insert_mode(new_mode) then
    leave_ascii_mode()
  end
end

-- Kept private by convention; useful for testing integrations without having
-- to synthesize Neovim's read-only ModeChanged event payload.
M._on_mode_changed = on_mode_changed

--- Configure and enable the plugin.
--- Idempotent: calling setup() again replaces the previous configuration.
---@param opts table|nil
function M.setup(opts)
  vim.validate({
    opts = { opts, "table", true },
  })

  -- A repeated setup() may select another schema. Restore through the old
  -- configuration before replacing it, so the saved value is not written to
  -- the newly configured engine.
  local new_config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  vim.validate({
    schema = { new_config.schema, "string", true },
    direct_mode = { new_config.direct_mode, "number" },
    notify = { new_config.notify, "boolean" },
  })

  leave_ascii_mode()
  config = new_config
  state.schema = nil
  notified = {}
  M._configured = true

  local group = vim.api.nvim_create_augroup("IBusTableRemote", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*",
    callback = function()
      on_mode_changed()
    end,
    desc = "ibus-table-remote: switch input mode with Neovim mode",
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      leave_ascii_mode()
    end,
    desc = "ibus-table-remote: restore input mode before quitting",
  })

  if is_ascii_mode(vim.api.nvim_get_mode().mode) then
    enter_ascii_mode()
  end
end

--- Print the current state, useful for debugging.
function M.status()
  local schema = resolve_schema()
  if not schema then
    vim.notify(
      "ibus-table-remote: cannot determine ibus-table schema",
      vim.log.levels.ERROR
    )
    return
  end

  local current = get_mode()
  local lines = {
    "ibus-table-remote",
    "  schema:    " .. schema,
    "  inputmode: " .. tostring(current),
    "  active:    " .. tostring(state.active),
    "  saved:     " .. tostring(state.saved or "-"),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("IBusTableRemoteStatus", M.status, {
  desc = "Show ibus-table-remote status",
  force = true,
})

return M
