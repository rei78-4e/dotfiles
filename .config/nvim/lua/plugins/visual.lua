return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    lazy = false,
    config = function()
      require("rose-pine").setup({
        styles = {
          transparency = true,
          bold = true,
          italic = true,
        },
        highlight_groups = {
          Visual = { bg = "iris", blend = 20 },
          Search = { bg = "gold", fg = "text", bold = true },
          IncSearch = { bg = "gold", fg = "text", bold = true, inherit = false },
          PmenuSel = { bg = "overlay", fg = "text", bold = true },
          MatchParen = { bg = "pine", fg = "text", bold = true },
          LspReferenceText = { bg = "highlight_med" },
          LspReferenceRead = { bg = "highlight_med" },
          LspReferenceWrite = { bg = "highlight_med" },
          -- Snacks picker highlights
          SnacksPickerCursor = { bg = "overlay", fg = "text", bold = true },
          SnacksPickerCursorLine = { bg = "overlay" },
          SnacksPickerSelect = { bg = "surface", fg = "iris", bold = true },
          SnacksIndent1 = { fg = "overlay" },
          SnacksIndent2 = { fg = "muted" },
          SnacksIndent3 = { fg = "iris" },
          SnacksIndent4 = { fg = "foam" },
          SnacksIndent5 = { fg = "gold" },
          SnacksIndent6 = { fg = "rose" },
          SnacksIndent7 = { fg = "love" },
          SnacksIndent8 = { fg = "pine" },
        },
      })

      -- Function to set colorscheme based on background
      local function set_colorscheme()
        if vim.o.background == "light" then
          vim.cmd.colorscheme("rose-pine-dawn")
        else
          vim.cmd.colorscheme("rose-pine-moon")
        end
      end

      -- Function to toggle between dark and light modes
      local function toggle_background()
        if vim.o.background == "dark" then
          vim.o.background = "light"
        else
          vim.o.background = "dark"
        end
        set_colorscheme()
      end

      -- Create user command for toggling
      vim.api.nvim_create_user_command("ToggleBackground", toggle_background, {})

      -- Set keymap for toggling (Leader + tb = toggle background)
      vim.keymap.set("n", "<leader>tb", toggle_background, { desc = "Toggle dark/light mode" })

      -- Neovim 0.12 queries the terminal background with OSC 11 before loading
      -- user config.  Preserve that result when the environment hint is absent
      -- (notably over SSH), and only override it when a terminal explicitly
      -- supplies a valid hint.
      if vim.env.TERM_BACKGROUND == "light" or vim.env.TERM_BACKGROUND == "dark" then
        vim.o.background = vim.env.TERM_BACKGROUND
      end

      set_colorscheme()
    end,
  },
  {
    "catgoose/nvim-colorizer.lua",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      filetypes = { "*" },
      options = {
        parsers = {
          names = { enable = false },
          hex = { default = false, rrggbb = true, rrggbbaa = true },
        },
        display = {
          mode = "background",
        },
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local function nyan()
        local current = vim.fn.line(".")
        local total = vim.fn.line("$")

        if total <= 1 then return "🌈 " end

        local width = 10
        local pos = math.floor((current - 1) / (total - 1) * width)

        return string.rep("=", pos) .. "( ^ｰ^)" .. string.rep("-", width - pos)
      end

      require("lualine").setup({
        options = {
          icons_enabled = true,
          theme = "auto",
          component_separators = "",
          section_separators = { left = "", right = "" },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = {
            {
              "filename",
              path = 1,
            },
            {
              function() return require("nvim-navic").get_location() end,
              cond = function() return require("nvim-navic").is_available() end,
            },
          },
          lualine_x = { "filesize", "filetype" },
          lualine_y = { nyan },
          lualine_z = { "location" },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {
            {
              "filename",
              path = 1,
            },
          },

          lualine_x = { nyan },
          lualine_y = {},
          lualine_z = {},
        },
        tabline = {},
        extensions = {},
      })
    end,
  },
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
      sign_priority = 6,
      watch_gitdir = {
        interval = 1000,
        follow_files = true,
      },
      current_line_blame = true,
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "right_align",
        delay = 50,
        ignore_whitespace = false,
      },
      current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
      update_debounce = 100,
      status_formatter = nil,
    },
    config = function(_, opts) require("gitsigns").setup(opts) end,
  },
  {
    "HiPhish/rainbow-delimiters.nvim",
    config = function()
      local rainbow_delimiters = require("rainbow-delimiters")
      vim.g.rainbow_delimiters = {
        strategy = {
          [""] = rainbow_delimiters.strategy["global"],
        },
        query = {
          [""] = "rainbow-delimiters",
        },
        highlight = {
          "RainbowDelimiterRed",
          "RainbowDelimiterYellow",
          "RainbowDelimiterBlue",
          "RainbowDelimiterOrange",
          "RainbowDelimiterGreen",
          "RainbowDelimiterViolet",
          "RainbowDelimiterCyan",
        },
      }
    end,
  },
  {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    opts = {
      provider_selector = function() return { "treesitter", "indent" } end,
    },
  },
  {
    "otnc/package-license-viewer",
    build = "npm ci && npm run compile:lsp",
    config = function()
      vim.opt.rtp:append(
        vim.fn.stdpath("data") .. "/lazy/package-license-viewer/packages/vim-plugin"
      )

      vim.cmd("runtime! plugin/package_license_viewer.vim")
    end,
  },
}
