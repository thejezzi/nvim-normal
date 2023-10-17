-- This file defines all additional behavior that is not common to
-- normalvim

vim.ool = function()
  vim.cmd [[highlight ColorColumn guibg=#1a1a1a]]
  vim.cmd [[highlight CursorLine guibg=#1a1a1a]]
  vim.cmd [[ highlight link LspCodeLens Comment ]]
end

vim.cmd("autocmd ColorScheme one-nvim lua vim.ool()")
