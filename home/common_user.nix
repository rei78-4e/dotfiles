{
  config,
  pkgs,
  inputs,
  lib,
  userName,
  standalone ? false,
  ...
}:
let
  dotfilesDir = "${config.home.homeDirectory}/dotfiles";
  npmGlobalDir = "${config.home.homeDirectory}/.npm-global";
  bunInstallDir = "${config.home.homeDirectory}/.cache/.bun";
  bunBinDir = "${bunInstallDir}/bin";

  system = pkgs.stdenv.hostPlatform.system;

  zathura-gui = inputs.zathura-gui.packages.${system}.default;
  niri-float-sticky = inputs.niri-float-sticky.packages.${system}.default;
  niri-scratchpad = inputs.niri-scratchpad.packages.${system}.default;
  zen-browser = inputs.zen-browser.packages.${system}.zen-browser;
  helium = inputs.helium-flake.packages.${system}.helium;

  helix-git = inputs.helix-git.packages.${system}.helix;

  emacsClient = pkgs.writeShellScriptBin "emacs" ''
    exec ${lib.getExe' pkgs.emacs-pgtk "emacsclient"} --create-frame "$@"
  '';
  emacsScratch = pkgs.writeShellScriptBin "emacs-scratch" ''
    # A second PGTK instance crashes while the daemon is running.  Make the
    # scratchpad a titled, floating frame in the existing daemon instead.
    exec ${lib.getExe' pkgs.emacs-pgtk "emacsclient"} \
      --create-frame \
      --frame-parameters='((title . "Scratchpad Emacs"))' \
      "$@"
  '';
  orgGitSync = pkgs.writeShellApplication {
    name = "org-git-sync";
    runtimeInputs = with pkgs; [
      coreutils
      git
    ];
    text = ''
      org_dir="${config.home.homeDirectory}/org"

      if [[ ! -e "$org_dir/.git" ]]; then
        echo "org-git-sync: $org_dir is not a Git repository" >&2
        exit 1
      fi

      cd "$org_dir"
      git pull
      git add .

      if ! git diff --cached --quiet; then
        changed_files_list="$(git diff --cached --name-only | paste -sd, -)"
        git commit -m "org mode chagens: $changed_files_list"
      fi

      git push
    '';
  };

  # `nix.gc` is a system service and does not manage profiles in this user's
  # XDG state directory.  Expire their generations before the nightly system
  # GC so their auto roots can become collectable.
  nixProfilePrune = pkgs.writeShellApplication {
    name = "nix-profile-prune";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      for profile in \
        "${config.home.homeDirectory}/.local/state/nix/profiles/profile" \
        "${config.home.homeDirectory}/.local/state/nix/profiles/home-manager"; do
        if [[ -L "$profile" ]]; then
          nix-env --profile "$profile" --delete-generations 7d
        fi
      done
    '';
  };
  packages = with pkgs; [
    # ===== git =====
    git
    gh
    ghq
    difftastic

    # ===== Editor =====
    vim
    neovim
    helix-git
    tree-sitter

    # ===== TUI =====
    yazi
    fzf
    fastfetch
    lazygit
    btop
    htop

    # ===== Shell =====
    fish

    # ===== cli =====
    fd
    ripgrep
    eza
    bat
    dust
    zip
    unzip
    tokei
    wget
    jq
    tmux-mem-cpu-load

    nil
    mediainfo

    # ===== nix =====
    direnv
    nix-direnv
    statix
    deadnix

    # ===== Media =====
    ffmpeg
    imagemagick

    # ===== PL =====
    cargo
    go
    gopls
    zig
    zls
    bun
    nodejs
    typescript
    clang
    clang-tools
    llvm
    lld

    tailscale

    # ===== Typst =====
    typst
    typstyle
    tinymist

    chafa

    # ===== AI =====
    codex
    opencode

    # ===== auth =====
    gnupg
    pinentry-qt

    # ===== Applications that do not require the host graphical stack =====
    restic
    nerd-fonts.symbols-only
    nerd-fonts.jetbrains-mono
    libnotify
    wl-clipboard
    wlrctl
    bluetui
    pulsemixer
    brightnessctl
    playerctl
    ffmpegthumbnailer
  ];

  # NixOS owns its graphical stack, so keeping these in its closure is useful.
  # On a generic Linux host, use the distro packages (or Flatpak) instead: they
  # use the host's GL, portal, input-method, and desktop integration directly.
  graphicalPackages = with pkgs; [
    # The user service uses an absolute store path, but interactive commands
    # still need the package in the user profile.
    noctalia
    kitty
    spotify
    google-chrome
    helium
    zathura
    sioyek
    pinta
    inkscape
    gimp
    nautilus
    loupe
    clapper # video viewer
    showtime
    libreoffice
    firefox
    discord
    slack
    gnome-text-editor
    gnome-tweaks
    kdePackages.kdenlive
    mpv
    ghostty
    vlc
    wiremix
    mpvpaper
    zathura-gui
    chromium
    geeqie
    digikam
    prismlauncher
    niri-float-sticky
    niri-scratchpad
    gnome-calendar
    thunderbird
    evolution
  ];

  # Keep small daily tools that Fedora's enabled repositories do not provide.
  standaloneNixPackages = with pkgs; [
    lazygit
    yazi
  ];

  mkConfigLink = name: config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/.config/${name}";
in
{
  imports = [ inputs.vicinae.homeManagerModules.default ];

  config = {
    home.username = lib.mkDefault userName;
    home.homeDirectory = lib.mkDefault "/home/${config.home.username}";
    home.stateVersion = "24.11";

    programs.home-manager.enable = true;

    programs.vicinae = lib.mkIf (!standalone) {
      enable = true;
      systemd = {
        enable = true;
        autoStart = true;
        environment.USE_LAYER_SHELL = 1;
      };
    };

    programs.gpg.enable = true;
    services.gpg-agent = {
      enable = true;
      enableZshIntegration = true;
      pinentry.package = pkgs.pinentry-qt;
      defaultCacheTtl = 43200;
      maxCacheTtl = 43200;
    };

    programs.zsh = {
      enable = true;
      dotDir = "${config.home.homeDirectory}/.config/zsh";
      enableCompletion = false;
      initContent = ''
        if [ -f "${dotfilesDir}/.zshrc" ]; then
          source "${dotfilesDir}/.zshrc"
        fi
      '';
    };

    programs.obs-studio = lib.mkIf (!standalone) {
      enable = true;

      plugins = with pkgs.obs-studio-plugins; [
        obs-pipewire-audio-capture
      ];
    };
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    gtk = {
      enable = true;
      cursorTheme = {
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
        size = 20;
      };
    };

    programs.tmux = {
      enable = true;
      package = pkgs.tmux;
      plugins = with pkgs.tmuxPlugins; [
        sensible
        yank
        battery
        cpu
        resurrect
        continuum
        {
          plugin = rose-pine;
          extraConfig = "set -g @rose_pine_variant 'dawn'";
        }
      ];
      extraConfig = "source-file ~/.config/tmux/.tmux.conf";
    };

    programs.emacs = lib.mkIf (!standalone) {
      enable = true;
      package = pkgs.emacs-pgtk;
      extraPackages = epkgs: [
        (epkgs.treesit-grammars.with-grammars (grammars: [
          grammars.tree-sitter-typst
        ]))
      ];
    };
    services.emacs = lib.mkIf (!standalone) {
      enable = true;
      startWithUserSession = "graphical";
      defaultEditor = true;
      client.enable = false;
      extraOptions = [
        "--no-init-file"
        "--load"
        "${dotfilesDir}/.config/emacs/init.el"
      ];
    };

    targets.genericLinux.enable = true;

    # ===== packages =====
    # A standalone Fedora host owns day-to-day packages through DNF.  Keep this
    # list for NixOS, where it is part of the declarative system closure.
    home.packages =
      lib.optionals standalone standaloneNixPackages
      ++ lib.optionals (!standalone) (
        packages
        ++ graphicalPackages
        ++ [
          (lib.hiPrio emacsClient)
          emacsScratch
        ]
      );

    home.sessionVariables = {
      NPM_CONFIG_PREFIX = npmGlobalDir;
      BUN_INSTALL = bunInstallDir;
      CC = "clang";
      CXX = "clang++";
      LD = "lld";
    };
    home.sessionPath = [
      "${npmGlobalDir}/bin"
      bunBinDir
    ];

    xdg.enable = true;
    xdg.configFile = {
      # programs.tmux generates tmux/tmux.conf, so link the editable files
      # individually instead of replacing its parent directory.
      "tmux/.tmux.conf" = {
        source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/.config/tmux/.tmux.conf";
      };
      "tmux/clipboard.sh" = {
        source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/.config/tmux/clipboard.sh";
      };
      "nvim" = {
        source = mkConfigLink "nvim";
        recursive = false;
      };
      "emacs" = {
        source = mkConfigLink "emacs";
        recursive = false;
      };
      "fastfetch" = {
        source = mkConfigLink "fastfetch";
        recursive = false;
      };
      "helix" = {
        source = mkConfigLink "helix";
        recursive = false;
      };
      "kitty" = {
        source = mkConfigLink "kitty";
        recursive = false;
      };
      "git" = {
        source = mkConfigLink "git";
        recursive = false;
      };
      "yazi" = {
        source = mkConfigLink "yazi";
        recursive = false;
      };
      "vim" = {
        source = mkConfigLink "vim";
        recursive = false;
      };
      "rofi" = {
        source = mkConfigLink "rofi";
        recursive = false;
      };
      "fish" = {
        source = mkConfigLink "fish";
        recursive = false;
      };
      "ziggity" = {
        source = mkConfigLink "ziggity";
        recursive = false;
      };
      "opencode" = {
        source = mkConfigLink "opencode";
        recursive = false;
      };
      "hypr" = {
        source = mkConfigLink "hypr";
        recursive = false;
      };
      "niri" = {
        source = mkConfigLink "niri";
        recursive = false;
      };
      "ghostty" = {
        source = mkConfigLink "ghostty";
        recursive = false;
      };
      "waybar" = {
        source = mkConfigLink "waybar";
        recursive = false;
      };
      "noctalia" = {
        source = mkConfigLink "noctalia";
        recursive = false;
      };
      "obs-studio" = {
        source = mkConfigLink "obs-studio";
        recursive = false;
      };
    };

    xdg.desktopEntries.emacs = lib.mkIf (!standalone) {
      name = "Emacs";
      genericName = "Text Editor";
      comment = "Edit text with the Emacs daemon";
      exec = "${lib.getExe' pkgs.emacs-pgtk "emacsclient"} --create-frame %F";
      icon = "emacs";
      terminal = false;
      categories = [
        "Development"
        "TextEditor"
      ];
      mimeType = [
        "text/plain"
        "text/x-c"
        "text/x-c++"
        "text/x-java"
        "text/x-makefile"
      ];
      settings.StartupWMClass = "Emacsd";
    };

    systemd.user.services.niri-float-sticky = {
      Unit = {
        Description = "Make picture-in-picture windows stick across niri workspaces";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe niri-float-sticky)
          "-title"
          "Picture in picture|Picture-in-Picture"
        ];
        Restart = "on-failure";
        RestartSec = 2;
        StandardOutput = "journal";
        StandardError = "journal";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.noctalia = {
      Unit = {
        Description = "Noctalia status bar";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        Conflicts = [ "waybar.service" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.noctalia}";
        Restart = "on-failure";
        RestartSec = 2;
        StandardOutput = "journal";
        StandardError = "journal";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist-clean = {
      Unit.Description = "Clean cliphist";

      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.cliphist} wipe";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.user.timers.cliphist-clean = {
      Unit.Description = "Clean cliphist every week";

      Timer = {
        OnCalendar = "weekly";
        Persistent = false;
      };

      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.nix-profile-prune = {
      Unit.Description = "Expire old Nix and Home Manager profile generations";

      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe nixProfilePrune;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.user.timers.nix-profile-prune = {
      Unit.Description = "Expire user profile generations before nightly Nix GC";

      Timer = {
        OnCalendar = "*-*-* 23:40:00";
        Persistent = true;
        Unit = "nix-profile-prune.service";
      };

      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.org-git-sync = {
      Unit = {
        Description = "Pull and commit changes in the org-mode repository";
        ConditionPathExists = "${config.home.homeDirectory}/org/.git";
      };

      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe orgGitSync;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.user.timers.org-git-sync = {
      Unit.Description = "Synchronize the org-mode repository every 5 minutes";

      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
        Unit = "org-git-sync.service";
        Persistent = false;
      };

      Install.WantedBy = [ "timers.target" ];
    };
  };
}
