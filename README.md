# ibus-table-remote.nvim

在 Neovim 的 Normal / Visual 模式中使用 ASCII（Direct），回到 Insert 模式时恢复原来的 ibus-table 输入状态。

适用于 Linux + GNOME/IBus 下的码表输入法（如郑码、五笔、拼音等 ibus-table 引擎）。

## 功能

- 进入 Normal / Visual / Select / Operator-pending 模式时，保存当前输入模式并切换到 Direct（英文直通）。
- 进入 Insert / Replace / Terminal 模式时，恢复进入 Normal 之前保存的输入模式。
- 退出 Neovim（`VimLeavePre`）时恢复输入模式，避免输入法停留在英文状态。
- 切换只依赖 `gsettings`，不需要重启 IBus 或输入法；自动识别码表时额外调用一次 `ibus engine`。
- 同步调用，无后台进程或定时器。

## 原理

ibus-table 每个码表都有一个可重定位的 GSettings schema：

```text
org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/<schema>/
```

其中 `inputmode` 键：`0 = Direct`（英文直通），`1 = Table`（码表输入）。运行中的引擎会监听该键的变化并立即切换，因此插件只需：

1. 进入 Normal / Visual 时 `gsettings get` 保存当前值，再 `gsettings set ... 0`；
2. 离开 Normal / Visual 时 `gsettings set` 恢复保存的值。

## 要求

- Linux，运行中的 IBus 与 ibus-table 输入法；
- Neovim >= 0.7（使用 `ModeChanged`、`nvim_create_augroup`）；
- `gsettings`、`ibus` 命令可用（一般随 GNOME/IBus 安装）。

## 安装

### lazy.nvim

```lua
{
  "uzvg/ibus-table-remote.nvim",
  opts = {
    schema = "zhengma",
  },
}
```

`opts` 会自动调用 `setup()`。如果省略 `opts`，插件会尝试从 `ibus engine` 自动识别当前码表。

### vim.pack（Neovim 0.12+）

```lua
vim.pack.add({
  "https://github.com/uzvg/ibus-table-remote.nvim",
})
```

无需额外配置即可工作（自动识别当前码表）。如需指定码表或修改选项：

```lua
vim.pack.add({
  "https://github.com/uzvg/ibus-table-remote.nvim",
})

require("ibus-table-remote").setup({
  schema = "zhengma",
})
```

## 配置

```lua
require("ibus-table-remote").setup({
  -- 码表名，例如 "zhengma"；也可以直接传完整的 gsettings schema 字符串。
  -- nil 表示自动从 `ibus engine` 识别（形如 table:zhengma）。
  schema = "zhengma",

  -- Direct / 英文模式对应的 inputmode 值，默认 0。
  direct_mode = 0,

  -- 是否通过 vim.notify 显示错误（同一条错误只提示一次），默认 true。
  notify = true,
})
```

可选值：

| 选项          | 类型      | 默认值 | 说明                                                           |
| ------------- | --------- | ------ | -------------------------------------------------------------- |
| `schema`      | `string`  | `nil`  | 码表名或完整 schema；`nil` 时用 `ibus engine` 自动识别          |
| `direct_mode` | `number`  | `0`    | Direct 模式的 `inputmode` 值                                    |
| `notify`      | `boolean` | `true` | 是否显示错误通知                                                |

## 如何获取 schema

1. 切换到要使用的 ibus-table 输入法，然后查看当前引擎：

   ```bash
   ibus engine
   ```

   输出形如：

   ```text
   table:zhengma
   ```

   其中冒号后的部分 `zhengma` 就是配置里的 `schema`。

2. 查看系统里所有码表引擎：

   ```bash
   ibus list-engine | grep '^table:'
   ```

3. 确认对应的 GSettings 路径和键（可选，用于排查）：

   ```bash
   gsettings list-keys org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/
   gsettings get org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/ inputmode
   gsettings set org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/ inputmode 0
   ```

   这里的 `zhengma` 替换成你的码表名即可（如 `wubi`、`pinyin`）。

`schema` 支持以下写法，三者等价：

```lua
schema = "zhengma"
schema = "table:zhengma"
schema = "org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/"
```

> 未设置 `schema` 时，插件在首次使用时执行一次 `ibus engine` 并缓存结果。如果同时使用多个 ibus-table 码表，建议显式配置，避免只控制启动时识别到的那个码表。

## 命令

```vim
:IBusTableRemoteStatus
```

显示当前 schema、实际 `inputmode`、插件是否处于激活状态以及保存的待恢复值，便于排查问题。

## 排查

- 确认 `:IBusTableRemoteStatus` 里的 schema 与 `ibus engine` 当前输出一致（例如 `table:zhengma` 对应 `zhengma`）。
- 由于 ibus-table 使用的是可重定位 schema，写错码表名时 `gsettings` 仍会接受，但不会有引擎监听该路径。此时模式不会真正切换，请用 `ibus list-engine | grep '^table:'` 核对名称。
- 手动验证底层开关是否有效：

  ```bash
  gsettings set org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/ inputmode 0
  gsettings set org.freedesktop.ibus.engine.table:/org/freedesktop/ibus/engine/table/zhengma/ inputmode 1
  ```

  观察输入法是否立即在英文/码表之间切换。

## 注意事项

- 切换作用于该码表在**所有应用**中的实例，而不是仅当前 Neovim 窗口。
- ibus-table 默认 `rememberinputmode=true`，模式值会持久化。插件退出时会恢复，但若 Neovim 异常崩溃，输入法可能停留在 Direct 模式，按一次 `Shift_L` 即可切回。
- 在 Normal 模式下按 `Shift_L` 手动切换仍然有效；下一次进入 Insert 时恢复的是进入 Normal 时保存的值。
- 该方案不切换全局输入法引擎（不是 `ibus engine xkb:us::eng`），只切换同一个 ibus-table 引擎内部的模式。
- Direct 模式不完全等于纯 ASCII，某些全角/半角转换仍可能生效。

## License

MIT
