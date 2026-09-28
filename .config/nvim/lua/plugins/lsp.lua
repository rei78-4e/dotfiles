return {
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      -- Prefer project-local dev shell tools and use Mason as a fallback.
      require("mason").setup({ PATH = "append" })

      require("mason-lspconfig").setup({
        ensure_installed = {
          -- "ts_ls",
          "lua_ls",
          "basedpyright",
          "astro",
          "html",
          "cssls",
          "emmet_ls",
        },
      })
    end,
  },
  {
    "saghen/blink.cmp",
    lazy = false,
    dependencies = "rafamadriz/friendly-snippets",
    version = "*",
    opts = {
      keymap = {
        preset = "default",
        ["<CR>"] = { "accept", "fallback" },
      },
      -- In Astro, the LSP often returns snippet-based completions that can replace text around
      -- the cursor. With blink's default `preselect=true` + `auto_insert=true`, pressing <CR>
      -- can unintentionally confirm a completion and overwrite the `}` inserted by autopairs.
      completion = {
        list = {
          selection = {
            preselect = function(_) return vim.bo.filetype ~= "astro" end,
            auto_insert = function(_) return vim.bo.filetype ~= "astro" end,
          },
        },
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono",
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        providers = {
          -- copyright / date などの展開は blink 内蔵の snippets ソース。
          -- 自前のものは `~/.config/nvim/snippets/*.json`（= dotfiles の .config/nvim/snippets）に置く。
          -- ファイル名が filetype 名、`all.json` は全 filetype で候補に出る。
          snippets = {
            opts = {
              -- friendly-snippets の global.json は自前の all.json と prefix が被るので外す
              -- (copyright / date / time / uuid ... は all.json 側で定義)
              filter_snippets = function(_, file)
                return not (file:match("friendly.snippets") and file:match("global%.json$"))
              end,
            },
          },
        },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
      {
        "SmiteshP/nvim-navic",
        opts = {
          lsp = {
            auto_attach = true,
          },
        },
      },
    },
    event = { "BufReadPre", "BufNewFile" },
    lazy = false,
    config = function()
      vim.diagnostic.config({
        virtual_text = false,
        update_in_insert = false,
        float = {
          border = "rounded",
          source = true,
        },
      })

      -- Make diagnostic float transparent
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
      vim.api.nvim_set_hl(0, "FloatBorder", { bg = "none" })

      local lspconfig = require("lspconfig")
      local capabilities = require("blink.cmp").get_lsp_capabilities()
      local navic = require("nvim-navic")

      navic.setup({
        lsp = {
          auto_attach = true,
        },
      })

      -- Defined as no-op to satisfy existing references in vim.lsp.config calls below
      local on_attach = function(client, bufnr) end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local bufnr = args.buf

          if client.server_capabilities.documentSymbolProvider then navic.attach(client, bufnr) end

          if client.server_capabilities.inlayHintProvider then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          end

          local opts = { buffer = bufnr, silent = true }
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "gd", function()
            vim.cmd("tab split")
            vim.lsp.buf.definition()
          end, opts)

          vim.api.nvim_create_autocmd("CursorHold", {
            buffer = bufnr,
            callback = function()
              vim.diagnostic.open_float(nil, {
                focusable = false,
                close_events = { "CursorMoved", "CursorMovedI", "BufLeave" },
                border = "rounded",
                source = "always",
                prefix = " ",
                scope = "line",
                header = "",
                winhighlight = "Normal:NormalFloat",
              })
            end,
          })
        end,
      })

      --  ╦   ╔═╗ ╔═╗      ╔═╗ ╔═╗ ╔╗╔ ╔═╗ ╦ ╔═╗
      --  ║   ╚═╗ ╠═╝      ║   ║ ║ ║║║ ╠╣  ║ ║ ╦
      --  ╩═╝ ╚═╝ ╩        ╚═╝ ╚═╝ ╝╚╝ ╚   ╩ ╚═╝

      vim.lsp.config("rust_analyzer", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "rust" },
        settings = {
          ["rust-analyzer"] = {
            cargo = {
              allFeatures = true,
            },
            check = {
              command = "clippy",
            },
            inlayHints = {
              enable = true,
              typeHints = true,
              parameterHints = true,
              chainingHints = true,
              lifetimeElisionHints = true,
              expressionAdjustmentHints = true,
              closureCaptureHints = true,
            },
          },
        },
      })
      vim.lsp.enable("rust_analyzer")

      vim.lsp.config("biome", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
      })
      vim.lsp.enable("biome")

      vim.lsp.config("tombi", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "toml" },
      })
      vim.lsp.enable("tombi")

      vim.lsp.config("clangd", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "c", "cpp", "objc", "objcpp" },
      })
      vim.lsp.enable("clangd")

      vim.lsp.config("gopls", {
        cmd = { "gopls" },
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "go", "gomod", "gowork", "gotmpl" },
        settings = {
          gopls = {
            hints = {
              parameterNames = true,
              assignVariableTypes = true,
            },
            analyses = { unusedparams = true, shadow = true },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })
      vim.lsp.enable("gopls")

      vim.lsp.config("ocamllsp", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = {
          "ocaml",
          "ocamlinterface",
          "ocamllex",
          "menhir",
          "dune",
        },
      })

      vim.lsp.enable("ocamllsp")

      vim.lsp.config("emmet_ls", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = {
          "html",
          "css",
          "scss",
          "sass",
          "less",
          "javascript",
          "javascriptreact",
          "typescriptreact",
          "astro",
        },
        init_options = {
          html = {
            options = {
              ["bem.enabled"] = true,
            },
          },
        },
      })
      vim.lsp.enable("emmet_ls")

      vim.lsp.config("astro", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "astro" },
      })
      vim.lsp.enable("astro")

      vim.lsp.config("zls", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = {
          "zig",
        },
      })
      vim.lsp.enable("zls")

      vim.lsp.config("html", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "html" },
      })
      vim.lsp.enable("html")

      vim.lsp.config("cssls", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "css", "scss", "less" },
      })
      vim.lsp.enable("cssls")

      vim.lsp.config("moonbit-lsp", {
        cmd = { "moonbit-lsp" },
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "moonbit" },
        root_dir = vim.fs.root(0, { "moon.mod.json", "moon.pkg.json" }),
      })
      vim.lsp.enable("moonbit-lsp")

      vim.lsp.config("prepoly", {
        cmd = { "prepoly-lsp" },
        on_attach = on_attach,
        filetypes = { "pp", "prepoly" },
      })
      vim.lsp.enable("prepoly")

      local hyprlnad_bin = vim.fn.exepath("Hyprland")
      local hypr_stubs = ""

      if hyprlnad_bin ~= "" then
        hypr_stubs = vim.fn.fnamemodify(hyprlnad_bin, ":h:h") .. "/share/hypr/stubs"
      end

      local lib = { vim.env.VIMRUNTIME }
      if vim.fn.isdirectory(hypr_stubs) == 1 then table.insert(lib, hypr_stubs) end

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            hint = {
              arrayIndex = "Disable",
            },
            runtime = {
              version = "LuaJIT",
            },
            diagnostics = {
              globals = { "vim" },
            },
            workspace = {
              library = lib,
              checkThirdParty = false,
            },
            telemetry = {
              enable = false,
            },
          },
        },
      })
      vim.lsp.enable("lua_ls")

      vim.lsp.config("luau_lsp", {
        capabilities = capabilities,
        on_attach = on_attach,
      })

      vim.lsp.enable("luau_lsp")

      vim.lsp.config("gleam", {
        capabilities = capabilities,
        on_attach = on_attach,
      })
      vim.lsp.enable("gleam")

      vim.lsp.config("basedpyright", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "python" },
        settings = {
          basedpyright = {
            analysis = {
              typeCheckingMode = "standard",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
            },
          },
        },
      })
      vim.lsp.enable("basedpyright")

      vim.lsp.config("tinymist", {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "typst" },
      })

      vim.lsp.enable("tinymist")

      -- Brass (.cz). Per the Brass docs, `czpm lsp` resolves package.toml deps
      -- before starting the server, and falls back to the plain `czls` server
      -- in directories without a package.toml, so the same config works anywhere.
      vim.filetype.add({ extension = { cz = "brass" } })

      vim.lsp.config("brass", {
        cmd = { "czpm", "lsp" },
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "brass" },
        root_dir = vim.fs.root(0, { "package.toml" }),
      })
      vim.lsp.enable("brass")
    end,
  },
  {
    "pmizio/typescript-tools.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      settings = {
        separate_diagnostic_server = true,
        publish_diagnostic_on = "insert_leave",

        tsserver_file_preferences = {
          includeInlayParameterNameHints = "all",
          includeInlayParameterNameHintsWhenArgumentMatchesName = true,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayVariableTypeHints = true,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayEnumMemberValueHints = true,
        },

        tsserver_format_options = {
          allowIncompleteCompletions = false,
          allowRenameOfImportPath = false,
        },
      },
    },
  },
  -- {
  --   "cordx56/rustowl",
  --   version = "*", -- Latest stable version
  --   build = "cargo install rustowl",
  --   lazy = false, -- This plugin is already lazy
  --   opts = {
  --     auto_enable = true,
  --   },
  -- },
}
