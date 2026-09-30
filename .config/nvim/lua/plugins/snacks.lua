return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      dashboard = { enabled = false },
      explorer = { enabled = false },
      indent = {
        enabled = true,
        indent = {
          hl = {
            "SnacksIndent1",
            "SnacksIndent2",
            "SnacksIndent3",
            "SnacksIndent4",
            "SnacksIndent5",
            "SnacksIndent6",
            "SnacksIndent7",
            "SnacksIndent8",
          },
        },
      },
      input = { enabled = true },
      picker = {
        enabled = true,
        ui_select = true,
        hidden = true,
        ignored = false,
        layout = {
          layout = {
            height = 0.95,
            width = 0.7,
            min_width = 140,
          },
        },
        sources = {
          files = {
            cmd = "fd",
            args = {
              "--hidden",
              "--exclude",
              ".git",
              "--exclude",
              "node_modules",
              "--exclude",
              "target",
              "--exclude",
              ".mooncakes",
              "--exclude",
              "build",
              "--exclude",
              ".obsidian",
            },
            win = {
              input = {
                keys = {
                  ["<CR>"] = { "edit_tab", mode = { "n", "i" } },
                },
              },
            },
          },
          grep = {
            hidden = true,
            cmd = "rg",
            regex = true,
            win = {
              input = {
                keys = {
                  ["<CR>"] = { "edit_tab", mode = { "n", "i" } },
                },
              },
            },
          },
        },
      },
      notifier = { enabled = true },
      quickfile = { enabled = false },
      scope = { enabled = true },
      scroll = {
        -- Neovide already provides pixel-based scrolling; avoid stacking animations.
        enabled = true,
        animate = {
          duration = {
            step = 10,
            total = 120,
          },
          easing = "linear",
        },
        animate_repeat = {
          delay = 100,
          duration = {
            step = 5,
            total = 50,
          },
          easing = "linear",
        },
      },
      statuscolumn = { enabled = false },
      words = { enabled = true },
      terminal = {
        enabled = true,
      },
    },
    keys = {
      {
        "<Leader>f",
        function() Snacks.picker.files() end,
        desc = "find files",
      },
      {
        "<Leader>/",
        function() Snacks.picker.grep() end,
        desc = "grep",
      },
      {
        "<Leader>m",
        function() Snacks.picker.marks() end,
        desc = "Marks",
      },
      {
        "<Leader>u",
        function() Snacks.picker.undo() end,
        desc = "Undo History",
      },
      {
        "<Leader>d",
        function() Snacks.picker.diagnostics() end,
        desc = "Diagnostics",
      },
      {
        "<Leader>s",
        function() Snacks.picker.lsp_symbols() end,
        desc = "LSP Symbols",
      },
      {
        "<Leader>S",
        function() Snacks.picker.lsp_workspace_symbols() end,
        desc = "LSP Workspace Symbols",
      },
      {
        "gr",
        function() Snacks.picker.lsp_references() end,
        nowait = true,
        desc = "References",
      },
      {
        "<Leader>l",
        function() Snacks.lazygit() end,
        desc = "lazygit",
      },
    },
  },
}
