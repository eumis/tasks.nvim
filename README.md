# tasks.nvim

Run shell commands(tasks) in dedicated terminal windows.

## Installation

- neovim required
- install using your favorite plugin manager

[lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{
    "eumis/tasks.nvim"
}
```

[mini.deps](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-deps.md)
```lua
add({
    source = "eumis/tasks.nvim"
})
```

[packer](https://github.com/wbthomason/packer.nvim)
```lua
use {
    "eumis/tasks.nvim"
}
```

## Usage

```lua
local tasks = require "tasks"

-- Add tasks
tasks.add("test all", "nvim --no-plugin --headless -c 'PlenaryBustedDirectory lua/tests'")
tasks.add("test current file", function(bufnr) return "nvim --headless -c 'PlenaryBustedFile " .. vim.fn.expand("#" .. bufnr) .. "'" end)

-- Run tasks
tasks.run("test all")

-- Open/close list of tasks
tasks.toggle_list()
```

```vim
:TasksRun test all
:TasksOpen test current file
:TasksOpenList
:TasksCloseList
:TasksToggleList
```

## Config

```lua
-- default values
require "tasks".setup {
    run_keys = { "r", "<cr>" }, -- keys to run task from tasks list
    open_keys = { "o" }, -- keys to open task buffer from tasks list
    get_list_win_config = get_float_win_config, -- returns config for vim.api.nvim_open_win for list window
    get_task_win_config = get_float_win_config -- returns config for vim.api.nvim_open_win for task window
}
```
