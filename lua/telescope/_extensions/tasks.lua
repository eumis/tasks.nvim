local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
    return
end

local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local previewers = require("telescope.previewers")

local get_task_finder = function()
    return finders.new_table({
        results = require "tasks".get_all(),
        ---@param entry Task
        entry_maker = function(entry)
            return {
                value = entry,
                ordinal = entry.name,
                display = entry.name
            }
        end,
    })
end

local define_preview = function(self, entry, _)
    ---@type Task
    local task = entry.value
    local lines = {}

    if task.cwd ~= nil then
        table.insert(lines, "cd " .. task.cwd)
    end

    local cmd = task.cmd
    if type(cmd) == "function" then
        cmd = cmd(self.state.bufnr)
    end
    if type(cmd) == "string" then
        cmd = { cmd }
    end
    for _, c in ipairs(cmd) do
        table.insert(lines, c)
    end

    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    require('telescope.previewers.utils').highlighter(self.state.bufnr, "bash")
end

local attach_mappings = function(_, map)
    map("i", "<cr>", function() require "tasks".run(action_state.get_selected_entry().value.name) end)
    map("n", "<cr>", function() require "tasks".run(action_state.get_selected_entry().value.name) end)

    map("i", "<c-o>", function() require "tasks".open(action_state.get_selected_entry().value.name) end)
    map("n", "<c-o>", function() require "tasks".open(action_state.get_selected_entry().value.name) end)

    return true
end

return telescope.register_extension({
    exports = {
        all = function(opts)
            opts = opts or {}
            require("telescope.pickers").new(opts, {
                prompt_title = "Tasks",
                finder = get_task_finder(),
                sorter = conf.generic_sorter({}),
                previewer = previewers.new_buffer_previewer({
                    define_preview = define_preview
                }),
                attach_mappings = attach_mappings
            }):find()
        end,
    },
})
