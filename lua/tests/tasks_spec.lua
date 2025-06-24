---@diagnostic disable: need-check-nil

local assert = require "luassert"
local reload = require "plenary.reload"

local M = {
    tasks = require "tasks"
}

local chansend_mock = {
    original = vim.fn.chansend,
    calls = {},
}

function chansend_mock.chansend(id, data)
    if chansend_mock.calls[id] == nil then
        chansend_mock.calls[id] = {}
    end
    table.insert(chansend_mock.calls[id], data)
end

local function setup()
    reload.reload_module("tasks")
    M.tasks = require "tasks"
    vim.fn.chansend = chansend_mock.chansend
end

local function cleanup()
    vim.fn.chansend = chansend_mock.original
    chansend_mock.calls = {}
end

---@param task_name string
---@return string
local function get_echo_output(task_name)
    return "echo output for " .. task_name
end

---@param name string
---@param add boolean?
local function create_echo_task(name, add)
    local task = {
        name = name,
        cmd = "echo \"" .. get_echo_output(name) .. "\""
    }
    if (add == true) then
        return M.tasks.add(task.name, task.cmd)
    end
    return task
end

---@param expected Task
---@param actual Task?
local function assert_task_equal(expected, actual)
    assert.is.Not.Nil(actual, "task")
    assert.are.equal(expected.name, actual.name, "task name")
    assert.are.equal(expected.cmd, actual.cmd, "task cmd")
end

---@param task Task
local function assert_task_view_opened(task)
    assert.are.equal(vim.api.nvim_get_current_win(), task.win, "task win")
    assert.are.equal(vim.api.nvim_get_current_buf(), task.buf, "task buf")
    assert.are.equal("terminal", vim.bo[task.buf].buftype)
end

---@param cmd string
---@param buf? integer
local function assert_cmd_run(cmd, buf)
    if buf == nil then buf = vim.api.nvim_get_current_buf() end
    local channel_id = vim.api.nvim_buf_get_var(buf, "terminal_job_id")

    local cmd_run = false
    if chansend_mock.calls[channel_id] ~= nil then
        for _, call_data in ipairs(chansend_mock.calls[channel_id]) do
            cmd_run = call_data[1] == cmd and call_data[2] == ""
            if cmd_run then break end
        end
    end

    assert.is.True(cmd_run, cmd .. " is run")
end

describe("task.add", function()
    before_each(setup)
    after_each(cleanup)

    it("should add task", function()
        local expected = create_echo_task("one")

        local actual = M.tasks.add(expected.name, expected.cmd)

        assert_task_equal(expected, actual)
    end)

    it("should add task with sort_order", function()
        local test_tasks = {
            create_echo_task("one"),
            create_echo_task("two"),
            create_echo_task("three"),
        }
        for i, task in ipairs(test_tasks) do
            local actual = M.tasks.add(task.name, task.cmd)
            assert.are.equal(i - 1, actual.sort_order, "task sort order")
        end
    end)

    it("should replace task with the same name", function()
        local name = "one"
        create_echo_task(name, true)
        local two = create_echo_task(name)
        two.cmd = "echo two"
        local created = M.tasks.add(two.name, two.cmd)

        local actual = M.tasks.get(name)

        assert.are.same(created, actual, "task")
        assert.are.equal(name, actual.name, "task name")
        assert.are.equal(two.cmd, actual.cmd, "task cmd")
        assert.are.equal(0, actual.sort_order, "task sort order")
    end)
end)

describe("task.get", function()
    before_each(setup)
    after_each(cleanup)

    it("should return nil for not existing task", function()
        assert.is.Nil(M.tasks.get("one"), "task")
    end)

    it("should return task", function()
        local expected = create_echo_task("one")
        M.tasks.add(expected.name, expected.cmd)

        local actual = M.tasks.get(expected.name)

        assert_task_equal(expected, actual)
    end)

    it("all should return all tasks", function()
        local test_tasks = {
            create_echo_task("one", true),
            create_echo_task("two", true),
            create_echo_task("three", true),
        }

        local actual_tasks = M.tasks.get_all()

        for i, task in ipairs(test_tasks) do
            local actual = actual_tasks[i]
            assert_task_equal(task, actual)
            assert.are.equal(i - 1, actual.sort_order, "task sort order")
        end
    end)
end)

local open_cases = {
    ["task.open"] = function(name) M.tasks.open(name) end,
    ["TasksOpen"] = function(name) vim.cmd("TasksOpen " .. name) end
}
for name, act in pairs(open_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should raise error if task not exist", function()
            local task_name = "some task"

            assert.has_error(function()
                act(task_name)
            end)
        end)

        it("should create win and buffer", function()
            local task = create_echo_task("one", true)

            act(task.name)

            assert_task_view_opened(task)
        end)

        it("should open existing win and buffer", function()
            local task = create_echo_task("one", true)
            M.tasks.open(task.name)
            local win = task.win
            local buf = task.buf

            act(task.name)

            assert_task_view_opened(task)
            assert.are.equal(win, task.win, "task win")
            assert.are.equal(buf, task.buf, "task buf")
        end)

        it("should cd to cwd", function()
            local cwd = "test/cwd"
            local task = M.tasks.add("test", "echo '1234'", { cwd = "test/cwd" })

            act(task.name)

            assert_cmd_run("cd " .. cwd)
        end)
    end)
end

local open_last_cases = {
    ["task.open_last"] = function() M.tasks.open_last() end,
    ["TasksOpenLast"] = function() vim.cmd("TasksOpenLast") end
}
for name, act in pairs(open_last_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should open last run task", function()
            local task = create_echo_task("one", true)
            M.tasks.run(task.name)
            vim.api.nvim_win_close(task.win, true)
            vim.api.nvim_buf_delete(task.buf, { force = true })

            act()

            assert_task_view_opened(task)
        end)
    end)
end

local run_cases = {
    ["task.run"] = function(name) M.tasks.run(name) end,
    ["TasksRun"] = function(name) vim.cmd("TasksRun " .. name) end
}
for name, act in pairs(run_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should raise error if task not exist", function()
            local task_name = "some task"

            assert.has_error(function()
                act(task_name)
            end)
        end)

        local run_tasks = {
            { name = "cmd", cmd = "echo \"cmd task\"",                            output = "echo \"cmd task\"" },
            { name = "fun", cmd = function() return "echo \"function task\"" end, output = "echo \"function task\"" },
        }
        for _, task_data in ipairs(run_tasks) do
            it("should run " .. task_data.name .. " task command", function()
                local task = M.tasks.add(task_data.name, task_data.cmd)

                act(task_data.name)

                assert_task_view_opened(task)
                assert_cmd_run(task_data.output)
            end)
        end

        local multiple_run_tasks = {
            { name = "cmd", cmd = { "echo \"cmd task\"", "echo \"second command\"" },                                  expected_cmd = "echo \"cmd task\" && echo \"second command\"" },
            { name = "fun", cmd = function() return { "echo \"function task\"", "echo \"second function task\"" } end, expected_cmd = "echo \"function task\" && echo \"second function task\"" },
        }
        for _, task_data in ipairs(multiple_run_tasks) do
            it("should run " .. task_data.name .. " task multiple commands", function()
                local task = M.tasks.add(task_data.name, task_data.cmd)

                act(task_data.name)

                assert_task_view_opened(task)
                assert_cmd_run(task_data.expected_cmd)
            end)
        end
    end)
end

local run_last_cases = {
    ["task.run_last"] = function() M.tasks.run_last() end,
    ["TasksRunLast"] = function() vim.cmd("TasksRunLast") end
}
for name, act in pairs(run_last_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should raise error if not task run yet", function()
            assert.has_error(function()
                act()
            end)
        end)

        local run_tasks = {
            { name = "cmd", cmd = "echo \"cmd task\"",                            output = "echo \"cmd task\"" },
            { name = "fun", cmd = function() return "echo \"function task\"" end, output = "echo \"function task\"" },
        }
        for _, task_data in ipairs(run_tasks) do
            it("should run " .. task_data.name .. " task command", function()
                local task = M.tasks.add(task_data.name, task_data.cmd)
                M.tasks.run(task.name)
                vim.api.nvim_win_close(task.win, true)
                vim.api.nvim_buf_delete(task.buf, { force = true })

                act()

                assert_task_view_opened(task)
                assert_cmd_run(task_data.output)
            end)
        end
    end)
end

local open_list_cases = {
    ["task.open_list"] = function() M.tasks.open_list() end,
    ["TasksOpenList"] = function() vim.cmd("TasksOpenList") end
}
for name, act in pairs(open_list_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should open task list", function()
            local test_tasks = {
                create_echo_task("one", true),
                create_echo_task("two", true),
                create_echo_task("three", true)
            }

            act()

            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            for i, task in ipairs(test_tasks) do
                assert.are.equal(task.name, lines[i], "task name")
            end
        end)
    end)
end

local close_list_cases = {
    ["task.close_list"] = function() M.tasks.close_list() end,
    ["TasksCloseList"] = function() vim.cmd("TasksCloseList") end
}
for name, act in pairs(close_list_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should close task list", function()
            M.tasks.open_list()
            local list_win = vim.api.nvim_get_current_win()

            act()

            assert.is.Not.True(vim.api.nvim_win_is_valid(list_win), "task win valid")
        end)
    end)
end

local toggle_list_cases = {
    ["task.toggle_list"] = function() M.tasks.toggle_list() end,
    ["TasksToggleList"] = function() vim.cmd("TasksToggleList") end
}
for name, act in pairs(toggle_list_cases) do
    describe(name, function()
        before_each(setup)
        after_each(cleanup)

        it("should open task list", function()
            M.tasks.close_list()
            local test_tasks = {
                create_echo_task("one", true),
                create_echo_task("two", true),
                create_echo_task("three", true)
            }

            act()

            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            for i, task in ipairs(test_tasks) do
                assert.are.equal(task.name, lines[i], "task name")
            end
        end)

        it("should close task list", function()
            M.tasks.open_list()
            local list_win = vim.api.nvim_get_current_win()

            act()

            assert.is.Not.True(vim.api.nvim_win_is_valid(list_win), "task win valid")
        end)
    end)
end

describe("task list", function()
    local run_keys = { "r", "e" }
    local open_keys = { "o", "s" }
    local test_tasks = {}

    before_each(function()
        setup()
        M.tasks.setup {
            run_keys = run_keys,
            open_keys = open_keys
        }
        test_tasks = {
            create_echo_task("one", true),
            create_echo_task("two", true),
            create_echo_task("three", true)
        }
    end)
    after_each(cleanup)

    for _, key in ipairs(run_keys) do
        for i = 1, 3 do
            it("should run task[" .. tostring(i) .. "] on " .. key, function()
                M.tasks.open_list()

                vim.api.nvim_win_set_cursor(0, { i, 1 })
                vim.cmd("normal " .. key)

                assert_task_view_opened(test_tasks[i])
                assert_cmd_run(test_tasks[i].cmd)
            end)
        end
    end

    for _, key in ipairs(open_keys) do
        for i = 1, 3 do
            it("should open task[" .. tostring(i) .. "] on " .. key, function()
                M.tasks.open_list()

                vim.api.nvim_win_set_cursor(0, { i, 1 })
                vim.cmd("normal " .. key)

                assert_task_view_opened(test_tasks[i])
            end)
        end
    end
end)
