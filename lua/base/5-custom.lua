-- This file defines all additional behavior that is not common to
-- normalvim

vim.ool = function()
  vim.cmd [[highlight ColorColumn guibg=#1a1a1a]]
  vim.cmd [[highlight CursorLine guibg=#1a1a1a]]
  vim.cmd [[ highlight link LspCodeLens Comment ]]
end

vim.nightfly_customization = function()
  -- Set FoldColumn highlight group to background color
  vim.cmd [[highlight FoldColumn guibg=NONE]]
  -- vim.cmd [[highlight ColorColumn guibg=#171717]]
end

vim.cmd("autocmd ColorScheme one-nvim lua vim.ool()")
vim.cmd("autocmd ColorScheme nightfly lua vim.nightfly_customization()")

vim.filetype.add({
    extension = {
        templ = "templ",
    },
})
