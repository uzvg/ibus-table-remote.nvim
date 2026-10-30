-- Auto-setup so the plugin works without configuration (e.g. vim.pack).
-- lazy.nvim calls setup() through opts/config during startup, which sets
-- _configured; the deferred call below then does nothing.
vim.schedule(function()
  local ok, plugin = pcall(require, "ibus-table-remote")
  if ok and not plugin._configured then
    plugin.setup()
  end
end)
