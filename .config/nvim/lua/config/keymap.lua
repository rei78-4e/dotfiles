vim.g.mapleader = " "

vim.keymap.set({ "n", "i", "v" }, "<C-n>", "<Esc><Cmd>tabnew<CR>")
vim.keymap.set("i", "jj", "<Esc>", { silent = true })

vim.keymap.set("n", "<Leader>a", vim.lsp.buf.code_action, { desc = "lsp code action" })
vim.keymap.set("n", "<Leader>r", vim.lsp.buf.rename, { desc = "lsp rename" })
vim.keymap.set("n", "<Leader>n", ":nohlsearch<CR>", { silent = true })
vim.keymap.set("n", "U", "<C-r>", { noremap = true, desc = "Redo" })
vim.keymap.set("n", "<C-b>", "<Nop>", { noremap = true })
vim.keymap.set(
  "n",
  "eh",
  ":lua vim.lsp.inlay_hint.enable(true, { bufnr = 0}) <CR>",
  { desc = "enable lsp inlay hint" }
)
vim.keymap.set({ "n", "i", "v" }, "<C-s>", function()
  vim.cmd("stopinsert")
  if vim.api.nvim_buf_get_name(0) == "" then
    local path = vim.fn.input("Save as: ", "", "file")
    if path == "" then return end
    vim.cmd("write " .. vim.fn.fnameescape(path))
  else
    vim.cmd("write")
  end
end, { desc = "Save buffer" })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })

-- vim.keymap.set("n", "p", '"0p')
-- vim.keymap.set("n", "P", '"0P')
-- vim.keymap.set({ "n", "v" }, "c", '"_c')
-- vim.keymap.set("n", "C", '"_C')

-- yank diagnostic from lsp
vim.keymap.set("n", "dc", function()
  local diags = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
  local cmap = {
    [1] = "Error",
    [2] = "Warn",
    [3] = "Info",
    [4] = "Hint",
  }

  if #diags > 0 then
    local d = diags[1]
    local red_lnum = 3

    local start_lnum_by_lsp = d.lnum + 1
    local end_line_by_lsp = d.end_lnum + 1

    -- nvim_buf_get_lines() return table
    local stt_lnum = math.min(start_lnum_by_lsp - red_lnum, start_lnum_by_lsp)
    local end_lnum = math.max(end_line_by_lsp, end_line_by_lsp + red_lnum + 1)

    local target_text =
      table.concat(vim.api.nvim_buf_get_lines(d.bufnr, stt_lnum, end_lnum, false), "\n")

    local ebuf = string.format(
      "%s: %s [%s] (Source: %s) at %d:%d-%d:%d\n%s\n",
      cmap[d.severity] or "Unknown",
      d.message,
      tostring(d.code or "N/A"),
      d.source or "N/A",
      start_lnum_by_lsp,
      d.col + 1,
      end_line_by_lsp,
      d.end_col + 1,
      target_text
    )

    vim.fn.setreg("+", ebuf)
    vim.notify("Diagnostic copied to clipboard!", vim.log.levels.INFO)
  else
    vim.notify("No diagnostics found on current line.", vim.log.levels.WARN)
  end
end, { desc = "Copy diagnostic message to clipboard" })

vim.keymap.set(
  "n",
  "<C-p>",
  ":Gitsigns preview_hunk_inline<CR>",
  { desc = "Preview git hunk inline" }
)

vim.keymap.set("n", "<C-p>", ":Gitsigns preview_hunk_inline<CR>")

-- improved increment function
vim.keymap.set("n", "<C-a>", function()
  local word = vim.fn.expand("<cword>")

  local toggles = { ["true"] = "false", ["false"] = "true" }

  if toggles[word] then
    vim.cmd("normal! ciw" .. toggles[word])
  else
    vim.cmd("normal! \1")
  end
end, { desc = "Increment or toggle boolean" })

-- improved decrement function
vim.keymap.set("n", "<C-x>", function()
  local word = vim.fn.expand("<cword>")

  local toggles = { ["true"] = "false", ["false"] = "true" }

  if toggles[word] then
    vim.cmd("normal! ciw" .. toggles[word])
  else
    vim.cmd("normal! \24")
  end
end, { desc = "Decrement or toggle boolean" })

vim.keymap.set("v", ":", [[:s/\v/g<Left><Left>]])
