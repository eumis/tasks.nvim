local M = {}

---@alias cmd string | string[] | fun(bufnr: integer): (string | string[])

---@class TaskParams
---@field cwd? string
---@field env? table<string, string | number | integer | boolean>

---@class Task
---@field name string
---@field cmd cmd
---@field cwd? string
---@field env? table<string, string | number | integer | boolean>
---@field buf integer
---@field win integer
---@field sort_order integer
---@field channel integer
---@field last_run number

---@alias sort
---| "recent"
---| "order"

---@class Options
---@field run_keys? string[]
---@field open_keys? string[]
---@field get_list_win_config? fun(): vim.api.keyset.win_config
---@field get_task_win_config? fun(): vim.api.keyset.win_config
---@field sort sort?

local state = {
    list_buf = -1,
    list_win = -1,
    current_buf = -1,
    ---@type {[string]: Task}
    tasks = {},
    tasks_count = 0,
    last_run_task = nil
}

---@return vim.api.keyset.win_config
local function get_float_win_config()
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)
    return {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal", -- No borders or extra UI elements
        border = "rounded",
    }
end

---@type Options
M.opts = {
    run_keys = { "r", "<cr>" },
    open_keys = { "o" },
    get_list_win_config = get_float_win_config,
    get_task_win_config = get_float_win_config
}

---@param name string
---@param cmd cmd
---@param params? TaskParams
function M.add(name, cmd, params)
    params = params or {}
    local existing = state.tasks[name]
    local new_task = {
        name = name,
        cmd = cmd,
        cwd = params.cwd,
        env = params.env,
        buf = -1,
        win = -1,
        sort_order = state.tasks_count,
        last_run = -state.tasks_count,
        channel = -1,
    }
    if existing ~= nil then
        new_task.buf = existing.buf
        new_task.win = existing.win
        new_task.sort_order = existing.sort_order
        new_task.channel = existing.channel
    end
    state.tasks_count = state.tasks_count + 1
    state.tasks[name] = new_task

    return new_task
end

---@param name string
---@return Task?
function M.get(name)
    return state.tasks[name]
end

---@return Task[]
function M.get_all()
    local tasks = {}
    for _, task in pairs(state.tasks) do
        table.insert(tasks, task)
    end
    if M.opts.sort == "recent" then
        table.sort(tasks, function(left, right) return left.last_run > right.last_run end)
    else
        table.sort(tasks, function(left, right) return left.sort_order < right.sort_order end)
    end
    return tasks
end

---@param task Task
local function ensure_task_buffer(task)
    if vim.api.nvim_win_is_valid(task.win) then return end

    if not vim.api.nvim_buf_is_valid(task.buf) then
        task.buf = vim.api.nvim_create_buf(false, true)
    end
    task.win = vim.api.nvim_open_win(task.buf, true, M.opts.get_task_win_config())
    if vim.bo[task.buf].buftype ~= "terminal" then
        vim.cmd.terminal()

        task.channel = vim.bo[task.buf].channel
        if task.cwd ~= nil then
            vim.fn.chansend(task.channel, { "cd " .. task.cwd, "" })
        end
        if task.env ~= nil then
            for key, value in pairs(task.env) do
                vim.fn.chansend(task.channel, { "export " .. key .. "='" .. value .. "'", "" })
            end
        end
    end
end

---@param name string
function M.open(name)
    local task = state.tasks[name]
    if task == nil then error("task " .. name .. " is not found") end
    ensure_task_buffer(task)
end

function M.open_last()
    local task = state.tasks[state.last_run_task]
    if task == nil then error("task not run yet") end
    M.open(task.name)
end

---@param name string
---@param bufnr? integer
function M.run(name, bufnr)
    local task = state.tasks[name]
    if task == nil then error("task " .. name .. " is not found") end
    if bufnr == nil then bufnr = vim.api.nvim_get_current_buf() end
    ensure_task_buffer(task)
    local cmd = task.cmd
    if type(cmd) == 'function' then
        cmd = cmd(bufnr)
    end
    if type(cmd) == 'table' then
        cmd = table.concat(cmd, ' && ')
    end

    vim.fn.chansend(task.channel, { cmd, "" })
    vim.cmd("normal G")
    state.last_run_task = name
    task.last_run = os.time()
end

function M.run_last()
    local task = state.tasks[state.last_run_task]
    if task == nil then error("task not run yet") end
    M.run(task.name)
end

function M.open_list()
    if vim.api.nvim_win_is_valid(state.list_win) then return end

    state.current_buf = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(state.list_buf) then
        state.list_buf = vim.api.nvim_create_buf(false, true)
        for _, key in ipairs(M.opts.run_keys) do
            vim.api.nvim_buf_set_keymap(state.list_buf, 'n', key, '', {
                callback = function()
                    local name = vim.api.nvim_get_current_line()
                    M.toggle_list()
                    M.run(name, state.current_buf)
                end
            })
        end

        for _, key in ipairs(M.opts.open_keys) do
            vim.api.nvim_buf_set_keymap(state.list_buf, 'n', key, '', {
                callback = function()
                    local name = vim.api.nvim_get_current_line()
                    M.toggle_list()
                    M.open(name)
                end
            })
        end
    end

    local tasks = {}
    for name, _ in pairs(state.tasks) do
        table.insert(tasks, name)
    end
    if M.opts.sort == "recent" then
        table.sort(tasks, function(left, right) return state.tasks[left].last_run > state.tasks[right].last_run end)
    else
        table.sort(tasks, function(left, right) return state.tasks[left].sort_order < state.tasks[right].sort_order end)
    end
    vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, tasks)

    state.list_win = vim.api.nvim_open_win(state.list_buf, true, M.opts.get_list_win_config())
end

function M.close_list()
    if vim.api.nvim_win_is_valid(state.list_win) then
        vim.api.nvim_win_hide(state.list_win)
    end
end

function M.toggle_list()
    if vim.api.nvim_win_is_valid(state.list_win) then
        M.close_list()
    else
        M.open_list()
    end
end

vim.api.nvim_create_user_command('TasksRun', function(opts) M.run(opts.fargs[1]) end, { nargs = 1 })
vim.api.nvim_create_user_command('TasksOpen', function(opts) M.open(opts.fargs[1]) end, { nargs = 1 })
vim.api.nvim_create_user_command('TasksOpenList', function() M.open_list() end, {})
vim.api.nvim_create_user_command('TasksCloseList', function() M.close_list() end, {})
vim.api.nvim_create_user_command('TasksToggleList', function() M.toggle_list() end, {})
vim.api.nvim_create_user_command('TasksRunLast', function() M.run_last() end, {})
vim.api.nvim_create_user_command('TasksOpenLast', function() M.open_last() end, {})

---@param opts Options
function M.setup(opts)
    for key, value in pairs(opts) do
        if value ~= nil then
            M.opts[key] = value
        end
    end
end

return M
