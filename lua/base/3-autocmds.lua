-- Autocmds file.
--
-- DESCRIPTION:
-- All autocmds are defined here.

--    Sections:
--
--       ## EXTRA LOGIC
--       -> 1. Events to load plugins faster.
--       -> 2. Save/restore window layout when possible.
--       -> 3. Launch alpha greeter on startup.
--       -> 4. Hot reload on config change.
--       -> 5. Update neotree when closing the git client.
--       -> 6. Java debugger.
--
--       ## COOL HACKS
--       -> 7. Effect: URL underline.
--       -> 8. Customize right click contextual menu.
--       -> 9. Unlist quickfix buffers if the filetype changes.
--       -> 10. Close all notifications on BufWritePre.
--
--       ## COMMANDS
--       -> 11. Nvim updater commands.
--       -> 12. Neotest commands.
--       ->     Extra commands.

local autocmd = vim.api.nvim_create_autocmd
local cmd = vim.api.nvim_create_user_command
local utils = require "base.utils"
local is_available = utils.is_available

-- ## EXTRA LOGIC -----------------------------------------------------------
-- 1. Events to load plugins faster → 'BaseFile'/'BaseGitFile':
--    this is pretty much the same thing as the event 'BufEnter',
--    but without increasing the startup time displayed in the greeter.
autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
  desc = "Nvim user events for file detection (BaseFile and BaseGitFile)",
  callback = function(args)
    local empty_buffer = vim.fn.resolve(vim.fn.expand "%") == ""
    local greeter = vim.api.nvim_get_option_value("filetype", { buf = args.buf }) == "alpha"
    local git_repo = utils.cmd(
      { "git", "-C", vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand "%"), ":p:h"), "rev-parse" }, false)

    -- For any file exept empty buffer, or the greeter (alpha)
    if not (empty_buffer or greeter) then
      utils.event "File" -- Emit event 'BaseFile'

      -- Is the buffer part of a git repo?
      if git_repo then
        utils.event "GitFile" -- Emit event 'BaseGitFile'
      end
    end
  end,
})

-- 2. Save/restore window layout when possible.
autocmd({ "BufWinLeave", "BufWritePost", "WinLeave" }, {
  desc = "Save view with mkview for real files",
  callback = function(args)
    if vim.b[args.buf].view_activated then
      vim.cmd.mkview { mods = { emsg_silent = true } }
    end
  end,
})
autocmd("BufWinEnter", {
  desc = "Try to load file view if available and enable view saving for real files",
  callback = function(args)
    if not vim.b[args.buf].view_activated then
      local filetype =
          vim.api.nvim_get_option_value("filetype", { buf = args.buf })
      local buftype =
          vim.api.nvim_get_option_value("buftype", { buf = args.buf })
      local ignore_filetypes = { "gitcommit", "gitrebase", "svg", "hgcommit" }
      if
          buftype == ""
          and filetype
          and filetype ~= ""
          and not vim.tbl_contains(ignore_filetypes, filetype)
      then
        vim.b[args.buf].view_activated = true
        vim.cmd.loadview { mods = { emsg_silent = true } }
      end
    end
  end,
})

-- 3. Launch alpha greeter on startup
if is_available "alpha-nvim" then
  autocmd({ "User", "BufEnter" }, {
    desc = "Disable status and tablines for alpha",
    callback = function(args)
      local is_filetype_alpha = vim.api.nvim_get_option_value(
        "filetype", { buf = 0 }) == "alpha"
      local is_empty_file = vim.api.nvim_get_option_value(
        "buftype", { buf = 0 }) == "nofile"
      if ((args.event == "User" and args.file == "AlphaReady") or
            (args.event == "BufEnter" and is_filetype_alpha)) and
          not vim.g.before_alpha
      then
        vim.g.before_alpha = {
          showtabline = vim.opt.showtabline:get(),
          laststatus = vim.opt.laststatus:get()
        }
        vim.opt.showtabline, vim.opt.laststatus = 0, 0
      elseif
          vim.g.before_alpha
          and args.event == "BufEnter"
          and not is_empty_file
      then
        vim.opt.laststatus = vim.g.before_alpha.laststatus
        vim.opt.showtabline = vim.g.before_alpha.showtabline
        vim.g.before_alpha = nil
      end
    end,
  })
  autocmd("VimEnter", {
    desc = "Start Alpha only when nvim is opened with no arguments",
    callback = function()
      -- Precalculate conditions.
      local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false)
      local buf_not_empty = vim.fn.argc() > 0
          or #lines > 1
          or (#lines == 1 and lines[1]:len() > 0)
      local buflist_not_empty = #vim.tbl_filter(
        function(bufnr) return vim.bo[bufnr].buflisted end,
        vim.api.nvim_list_bufs()
      ) > 1
      local buf_not_modifiable = not vim.o.modifiable

      -- Return instead of opening alpha if any of these conditions occur.
      if buf_not_modifiable or buf_not_empty or buflist_not_empty then
        return
      end
      for _, arg in pairs(vim.v.argv) do
        if arg == "-b"
            or arg == "-c"
            or vim.startswith(arg, "+")
            or arg == "-S"
        then
          return
        end
      end

      -- All good? Show alpha.
      require("alpha").start(true, require("alpha").default_config)
      vim.schedule(function() vim.cmd.doautocmd "FileType" end)
    end,
  })
end

-- 4. Hot reload on config change.
autocmd({ "BufWritePost" }, {
  desc = "When writing a buffer, :NvimReload if the buffer is a config file.",
  callback = function()
    local filesThatTriggerReload = {
      vim.fn.stdpath "config" .. "lua/base/1-options.lua",
      vim.fn.stdpath "config" .. "lua/base/4-mappings.lua",
    }

    local bufPath = vim.fn.expand "%:p"
    for _, filePath in ipairs(filesThatTriggerReload) do
      if filePath == bufPath then vim.cmd "NvimReload" end
    end
  end,
})

-- 5. Update neotree when closin the git client.
if is_available "neo-tree.nvim" then
  autocmd("TermClose", {
    pattern = { "*lazygit", "*gitui" },
    desc = "Refresh Neo-Tree git when closing lazygit/gitui",
    callback = function()
      local manager_avail, manager = pcall(require, "neo-tree.sources.manager")
      if manager_avail then
        for _, source in ipairs {
          "filesystem",
          "git_status",
          "document_symbols",
        } do
          local module = "neo-tree.sources." .. source
          if package.loaded[module] then
            manager.refresh(require(module).name)
          end
        end
      end
    end,
  })
end

-- 6. Java debugger.
if is_available "nvim-dap" then
  autocmd("BufRead", {
    desc = "On java files, start jdtls",
    callback = function()
      if vim.bo.filetype == "java" then
        local config = {
          cmd = { vim.fn.stdpath "data" .. "/mason/packages/jdtls/jdtls" },
          root_dir = vim.fs.dirname(vim.fs.find({ "gradlew", ".git", "mvnw" }, { upward = true })[1]),
          init_options = {
            bundles = {
              vim.fn.glob(vim.fn.stdpath "data" .. "/mason/packages/java-test/extension/server/*.jar", true),
              vim.fn.glob(
                vim.fn.stdpath "data" ..
                "/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
            },
          },
        }
        require("jdtls").start_or_attach(config)

        -- Give enough time for jdt to fully load the project, or it will fail with
        -- "No LSP client found"
        local timer = 2500
        for _ = 0, 12, 1 do
          vim.defer_fn(
            function()
              require("jdtls.dap").setup_dap_main_class_configs()
            end,
            timer
          )
          timer = timer + 2500
        end
      end
    end,
  })
end

-- ## COOL HACKS ------------------------------------------------------------
-- 7. Effect: URL underline.
autocmd({ "VimEnter", "FileType", "BufEnter", "WinEnter" }, {
  desc = "URL Highlighting",
  callback = function() utils.set_url_effect() end,
})

-- 8. Customize right click contextual menu.
autocmd("VimEnter", {
  desc = "Disable right contextual menu warning message",
  callback = function()
    -- Disable right click message
    vim.api.nvim_command [[aunmenu PopUp.How-to\ disable\ mouse]]
    -- vim.api.nvim_command [[aunmenu PopUp.-1-]] -- You can remode a separator like this.
    vim.api.nvim_command [[menu PopUp.Toggle\ \Breakpoint <cmd>:lua require('dap').toggle_breakpoint()<CR>]]
    vim.api.nvim_command [[menu PopUp.-2- <Nop>]]
    vim.api.nvim_command [[menu PopUp.Start\ \Compiler <cmd>:CompilerOpen<CR>]]
    vim.api.nvim_command [[menu PopUp.Start\ \Debugger <cmd>:DapContinue<CR>]]
    vim.api.nvim_command [[menu PopUp.Run\ \Test <cmd>:Neotest run<CR>]]
    vim.api.nvim_command [[menu PopUp.-3- <Nop>]] -- You can remode a separator like this.
    vim.api.nvim_command [[menu PopUp.Set\ \Filetype <cmd>:FLOSetFileType<CR>]]
  end,
})

-- 9. Unlist quickfix buffers if the filetype changes.
autocmd("FileType", {
  desc = "Unlist quickfist buffers",
  pattern = "qf",
  callback = function() vim.opt_local.buflisted = false end,
})

-- 10. Close all notifications on BufWritePre.
autocmd("BufWritePre", {
  desc = "Close all notifications on BufWritePre",
  callback = function()
    require("notify").dismiss({ pending = true, silent = true })
  end,
})

-- ## COMMANDS --------------------------------------------------------------
-- 11. Nvim updater commands
cmd(
  "NvimChangelog",
  function() require("base.utils.updater").changelog() end,
  { desc = "Check Nvim Changelog" }
)
cmd(
  "NvimUpdatePlugins",
  function() require("base.utils.updater").update_packages() end,
  { desc = "Update Plugins and Mason" }
)
cmd(
  "NvimRollbackCreate",
  function() require("base.utils.updater").create_rollback(true) end,
  { desc = "Create a rollback of '~/.config/nvim'." }
)
cmd(
  "NvimRollbackRestore",
  function() require("base.utils.updater").rollback() end,
  { desc = "Restores '~/.config/nvim' to the last rollbacked state." }
)
cmd(
  "NvimFreezePluginVersions",
  function() require("base.utils.updater").generate_snapshot(true) end,
  { desc = "Lock package versions (only lazy, not mason)." }
)
cmd(
  "NvimUpdateConfig", function() require("base.utils.updater").update() end,
  { desc = "Update Nvim distro" }
)
cmd(
  "NvimVersion",
  function() require("base.utils.updater").version() end,
  { desc = "Check Nvim distro Version" }
)
cmd(
  "NvimReload",
  function() require("base.utils").reload() end,
  { desc = "Reload Nvim without closing it (Experimental)" }
)

-- 12. Testing commands
-- Additional commands to the ones implemented in neotest.
-------------------------------------------------------------------

-- Customize this command to work as you like
cmd("TestNodejs", function()
  vim.cmd ":ProjectRoot"                  -- cd the project root (requires project.nvim)
  vim.cmd ":TermExec cmd='npm run tests'" -- convention to run tests on nodejs
  -- You can generate code coverage by add this to your project's packages.json
  -- "tests": "jest --coverage"
end, { desc = "Run all unit tests for the current nodejs project" })

-- Customize this command to work as you like
cmd("TestNodejsE2e", function()
  vim.cmd ":ProjectRoot"                -- cd the project root (requires project.nvim)
  vim.cmd ":TermExec cmd='npm run e2e'" -- Conventional way to call e2e in nodejs (requires ToggleTerm)
end, { desc = "Run e2e tests for the current nodejs project" })

-- Extra commands
----------------------------------------------

-- Change working directory
cmd("Cwd", function()
  vim.cmd ":cd %:p:h"
  vim.cmd ":pwd"
end, { desc = "cd current file's directory" })

-- Set working directory (alias)
cmd("Swd", function()
  vim.cmd ":cd %:p:h"
  vim.cmd ":pwd"
end, { desc = "cd current file's directory" })

-- Write all buffers
cmd("WriteAllBuffers", function()
  vim.cmd "wa"
end, { desc = "Write all changed buffers" })

-- Close all notifications
cmd("CloseNotifications", function()
  require("notify").dismiss({ pending = true, silent = true })
end, { desc = "Dismiss all notifications" })


-- Change filetype of current buffer with telescope
cmd("FLOSetFileType", function()
  local actions = require("telescope.actions")
  local actions_state = require("telescope.actions.state")
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")

  local function enter(prompt_bufnr)
    local selected = actions_state.get_selected_entry()
    actions.close(prompt_bufnr)

    vim.cmd("setfiletype " .. selected[1])
  end

  local filetypes_list = vim.fn.getcompletion('', 'filetype')

  local opts = {
    finder = finders.new_table(filetypes_list),
    sorter = sorters.get_generic_fuzzy_sorter({}),

    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", enter)
      return true
    end
  }

  local filetypes = pickers.new(opts)

  filetypes:find()

  -- vim.g.flo_handle_fzf_result = function()
  --   -- Schließen Sie das Terminalfenster
  --
  --   -- Holen Sie das Ergebnis von fzf
  --   local result = vim.fn.getline(1)
  --
  --   vim.api.nvim_win_close(0, true)
  --   -- Hier können Sie weitere Aktionen mit dem Ergebnis durchführen
  --
  --   vim.defer_fn(function()
  --     vim.cmd("setfiletype " .. result)
  --   end, 100)
  -- end
  --
  -- local filetypes_list = vim.fn.getcompletion('', 'filetype')
  -- local filetypes_string = table.concat(filetypes_list, '\n')
  --
  -- local fzf_cmd = 'echo "' .. filetypes_string .. '" | fzf'
  -- local buf = vim.api.nvim_create_buf(false, true)
  -- vim.cmd(string.format("autocmd TermClose <buffer=%s> lua vim.g.flo_handle_fzf_result()", buf))
  --
  -- local win_width = math.ceil(vim.o.columns * 0.7)
  -- local win_height = math.ceil(vim.o.lines * 0.7)
  -- local win_col = math.ceil((vim.o.columns - win_width) / 2)
  -- local win_row = math.ceil((vim.o.lines - win_height) / 2)
  -- local opts = {
  --   relative = 'editor',
  --   width = win_width,
  --   height = win_height,
  --   col = win_col,
  --   row = win_row,
  --   style = 'minimal'
  -- }
  -- local win = vim.api.nvim_open_win(buf, true, opts)
  --
  -- -- Starten Sie das Neovim-Terminal mit dem `fzf`-Befehl
  -- vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  -- vim.api.nvim_win_set_option(win, 'winblend', 8)
  -- vim.fn.termopen(fzf_cmd)
  -- vim.defer_fn(function()
  --   vim.cmd("startinsert")
  -- end, 100)
  --
  -- -- Setzen Sie den Fokus auf das Terminalfenster
  -- vim.api.nvim_set_current_win(win)
end, { desc = "Change filetype of current buffer" })
