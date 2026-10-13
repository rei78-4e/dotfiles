-- Disable netrw (default file explorer)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.list = true
vim.opt.listchars = {
  tab = "› ",
  trail = "~",
  nbsp = "␣",
}
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.showbreak = "⤷ "
vim.opt.clipboard = "unnamedplus"

vim.opt.scrolloff = 3

-- SSH / tmux 越しではローカルの wl-copy/wl-paste が使えないので、OSC52 で
-- クライアント端末 (kitty / ghostty) のクリップボードへ直接渡す。
-- ローカル (コンソール) では従来どおり Wayland クリップボードを使う。
if vim.env.SSH_CONNECTION or vim.env.SSH_TTY or vim.env.TMUX then
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = osc52.paste("+"),
      ["*"] = osc52.paste("*"),
    },
  }
end
vim.opt.hlsearch = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.updatetime = 1000
vim.opt.cursorline = true

vim.opt.foldtext = ""
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldcolumn = "auto"

vim.opt.mouse = "a"
vim.opt.signcolumn = "yes"
-- vim.opt.colorcolumn = "100"
vim.opt.autoread = true
vim.opt.modeline = false

vim.opt.autowriteall = true

vim.api.nvim_create_autocmd({ "InsertLeave", "FocusLost" }, {
  callback = function() vim.cmd("silent! wall") end,
})

vim.cmd(
  [[
  syntax match DangerousChars /[\u200B\u200C\u200D\uFEFF\u202E\u2066-\u2069]/
  highlight DangerousChars ctermbg=red guibg=red
]],
  false
)

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  pattern = "*",
  command = "checktime",
})

vim.filetype.add({
  extension = {
    mbt = "moonbit",
  },
})

-- Show default intro screen when opening a directory
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local arg = vim.fn.argv(0)
    if arg ~= "" and vim.fn.isdirectory(arg) == 1 then
      vim.cmd("bdelete")
      vim.cmd("intro")
      -- Map Enter to open file picker on intro screen
      vim.keymap.set(
        "n",
        "<CR>",
        function() require("snacks").picker.files() end,
        { buffer = 0, nowait = true }
      )
    end
  end,
})

vim.filetype.add({
  extension = {
    prepoly = "pp",
    pp = "pp",
    -- pp = "prepoly",
  },
})
