{
  config,
  pkgs,
  lib,
  ...
}:
let
  secretService = pkgs.writeShellScript "session-secret-service" ''
    case ":''${XDG_CURRENT_DESKTOP:-}:" in
      *:niri:*)
        # Complete PAM startup before D-Bus can launch another daemon.
        ${pkgs.systemd}/bin/systemctl --user start niri-kwallet.service
        exec ${pkgs.kdePackages.kwallet}/bin/ksecretd
        ;;
      *)
        exec /run/wrappers/bin/gnome-keyring-daemon --start --foreground --components=secrets
        ;;
    esac
  '';

  waybarLaunch = pkgs.writeShellScript "waybar-launch" ''
    set -eu
    BASE="$HOME/dotfiles/.config/waybar"
    case "''${XDG_CURRENT_DESKTOP:-}" in
      niri)
        exec ${pkgs.waybar}/bin/waybar -c "$BASE/config.niri.jsonc" -s "$BASE/style.css"
        ;;
      sway:wlroots)
        exec ${pkgs.waybar}/bin/waybar -c "$BASE/config.sway.jsonc" -s "$BASE/style.css"
        ;;
      *)
        exec ${pkgs.waybar}/bin/waybar -c "$BASE/config.hypr.jsonc" -s "$BASE/style.css"
        ;;
    esac
  '';

  swayncLaunch = pkgs.writeShellScript "swaync-launch" ''
    set -eu
    BASE="$HOME/dotfiles/.config/swaync"
    case "''${XDG_CURRENT_DESKTOP:-}" in
      niri)
        exec ${pkgs.swaynotificationcenter}/bin/swaync -s "$BASE/style.css"
        ;;
      *)
        exec ${pkgs.swaynotificationcenter}/bin/swaync
        ;;
    esac
  '';

  cliphistStore = pkgs.writeShellScript "cliphist-store" ''
    set -eu
    ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store &
    ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store &
    wait
  '';

  swayidleBrightnessDown = pkgs.writeShellScript "swayidle-brightness-down" ''
    exec /run/current-system/sw/bin/brightnessctl -s set 10%
  '';
  swayidleBrightnessUp = pkgs.writeShellScript "swayidle-brightness-up" ''
    exec /run/current-system/sw/bin/brightnessctl -r
  '';
  swayidleLockOff = pkgs.writeShellScript "swayidle-lock-off" ''
    [ "$(cat /sys/class/power_supply/AC/online)" != 1 ] \
      && ! /run/current-system/sw/bin/pw-dump \
        | /run/current-system/sw/bin/jq -e 'any(.[]; .info.props."media.class"=="Stream/Output/Audio" and .info.state=="running")' >/dev/null \
      && loginctl lock-session
    if pidof niri >/dev/null; then
      /run/current-system/sw/bin/niri msg action power-off-monitors
    else
      /run/current-system/sw/bin/hyprctl dispatch dpms off
    fi
  '';
  swayidleMonitorsOn = pkgs.writeShellScript "swayidle-monitors-on" ''
    if pidof niri >/dev/null; then
      /run/current-system/sw/bin/niri msg action power-on-monitors
    else
      /run/current-system/sw/bin/hyprctl dispatch dpms on
    fi
  '';
  idleSuspendThenHibernate = config.systemd.sleep.settings.Sleep.AllowSuspendThenHibernate or false;
  swayidleSleep = pkgs.writeShellScript "swayidle-sleep" ''
    set -euo pipefail
    [ "$(cat /sys/class/power_supply/AC/online)" = 0 ] || exit 0

    ${lib.optionalString idleSuspendThenHibernate ''
      lid=$(${pkgs.systemd}/bin/busctl get-property \
        org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager LidClosed)
      [ "$lid" = "b false" ] || exit 0
    ''}

    operation="$1"
    case "$operation" in
      suspend-then-hibernate) method=CanSuspendThenHibernate ;;
      hibernate) method=CanHibernate ;;
      *) exit 2 ;;
    esac
    can_sleep() {
      local capability
      capability=$(${pkgs.systemd}/bin/busctl --json=short call \
        org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager "$1") || return 1
      /run/current-system/sw/bin/jq -e '.data == ["yes"]' \
        <<< "$capability" >/dev/null
    }
    if ! can_sleep "$method"; then
      # Still suspend at 15 minutes if hibernation is temporarily unavailable.
      [ "$operation" = suspend-then-hibernate ] || exit 0
      can_sleep CanSuspend || exit 0
      operation=suspend
    fi
    exec ${pkgs.systemd}/bin/systemctl --no-ask-password "$operation"
  '';

  swayidleLock = pkgs.writeShellScript "swayidle-lock" ''
    ${lib.getExe pkgs.hyprlock}
    loginctl unlock-session
  '';

  swayidleLaunch = pkgs.writeShellScript "swayidle-launch" ''
    exec ${pkgs.swayidle}/bin/swayidle -w \
      timeout 480 ${swayidleBrightnessDown} resume ${swayidleBrightnessUp} \
      timeout 3600 ${swayidleLockOff} resume ${swayidleMonitorsOn} \
      ${lib.optionalString idleSuspendThenHibernate "timeout 900 '${swayidleSleep} suspend-then-hibernate'"} \
      timeout 1800 '${swayidleSleep} hibernate' \
      lock ${swayidleLock} \
      before-sleep 'loginctl lock-session'
  '';
in
{
  # ===== desktop base (entire system) =====
  services.desktopManager.gnome.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "niri";
  programs.ssh.askPassword = "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";
  programs.niri.enable = true;
  # Secret Service activation must select the same wallet as the session.
  # PAM starts GNOME Keyring with --login (initialization is deferred); keep
  # that password handoff for GNOME, but do not initialize it under niri.
  home-manager.sharedModules = [
    {
      xdg.dataFile."dbus-1/services/org.freedesktop.secrets.service".text = ''
        [D-BUS Service]
        Name=org.freedesktop.secrets
        Exec=${secretService}
      '';
      xdg.configFile = lib.genAttrs
        [ "autostart/gnome-keyring-secrets.desktop" "autostart/gnome-keyring-pkcs11.desktop" ]
        (name: {
          text = ''
            [Desktop Entry]
            Type=Application
            Name=GNOME Keyring
            Exec=/run/wrappers/bin/gnome-keyring-daemon --start --components=${if lib.hasInfix "pkcs11" name then "pkcs11" else "secrets"}
            NotShowIn=niri;
            NoDisplay=true
            X-GNOME-Autostart-Phase=PreDisplayServer
            X-GNOME-AutoRestart=false
            X-GNOME-Autostart-Notify=true
          '';
        });
    }
  ];
  # niri-session imports PAM's environment; this helper passes the ready
  # Wayland session environment to the KWallet daemon started by PAM.
  security.pam.services.login.kwallet.enable = true;
  systemd.user.services.niri-kwallet = {
    description = "Unlock KWallet in niri using the login password";
    unitConfig = {
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
      RemainAfterExit = true;
    };
    wantedBy = [ "graphical-session.target" ];
  };
  xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" = lib.mkForce "kwallet";
  programs.hyprlock.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  security.polkit.enable = true;
  systemd.packages = [ pkgs.hyprpolkitagent ];
  systemd.user.services.hyprpolkitagent.wantedBy = [ "graphical-session.target" ];
  systemd.user.services = {
    udiskie = {
      description = "udiskie automount daemon";
      unitConfig = {
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.udiskie} -a -t --notify";
        Restart = "on-failure";
      };
      wantedBy = [ "graphical-session.target" ];
    };

    cliphist-store = {
      description = "cliphist clipboard store";
      unitConfig = {
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      serviceConfig = {
        ExecStart = "${cliphistStore}";
        Restart = "on-failure";
      };
      wantedBy = [ "graphical-session.target" ];
    };

    waybar = {
      description = "Waybar status bar";
      unitConfig = {
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "swaync.service"
        ];
        Conflicts = [ "noctalia.service" ];
        Requires = [ "swaync.service" ];
      };
      serviceConfig = {
        ExecStart = waybarLaunch;
        Restart = "on-failure";
        Environment = [ "PATH=/run/current-system/sw/bin" ];
      };
    };

    swaync = {
      description = "SwayNC notification daemon for Waybar";
      unitConfig = {
        PartOf = [ "waybar.service" ];
        After = [ "graphical-session.target" ];
        Conflicts = [ "noctalia.service" ];
      };
      serviceConfig = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = swayncLaunch;
        Restart = "on-failure";
      };
    };

    swayidle = {
      description = "Idle manager for Wayland";
      unitConfig = {
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      serviceConfig = {
        ExecStart = swayidleLaunch;
        Restart = "on-failure";
        Environment = [ "PATH=/run/current-system/sw/bin" ];
      };
      wantedBy = [ "graphical-session.target" ];
    };
  };
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  services.upower.enable = true;

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;

  services.keyd = {
    enable = true;

    keyboards.default.settings.main = {
      pageup = "noop";
      pagedown = "noop";

      rightcontrol = "rightcontrol";

      assistant = "rightmeta";

      delete = "timeout(noop, 300, coffee)";
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };
  programs.virt-manager.enable = true;

  services.tlp = {
    enable = true;

    settings = {
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "low-power";
    };
  };
  services.power-profiles-daemon.enable = false;

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", KERNEL=="1-14", ATTR{idVendor}=="8087", ATTR{idProduct}=="0a2b", ATTR{authorized}="0"
  '';

  fonts = {
    packages = with pkgs; [
      monaspace
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      nerd-fonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      sansSerif = [
        "Noto Sans"
        "Noto Sans CJK JP"
      ];
      serif = [
        "Noto Serif"
        "Noto Serif CJK JP"
      ];
      monospace = [
        "Monaspace Radon"
        "Noto Sans Mono CJK JP"
        "Symbols Nerd Font Mono"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  environment.systemPackages = with pkgs; [
    brightnessctl
    jq
    waybar
    swaynotificationcenter
    rofi
    hyprpaper
    swayidle
    hyprpolkitagent
    hyprpicker
    hyprshot
    wl-clipboard
    kitty
    cliphist
    swtpm
    udiskie
    usbutils
    # niri 26.04+ provides X11 exclusively through xwayland-satellite
    # (on-demand). Without it there is no X server at all: DISPLAY stays empty
    # and X clients (Steam, etc.) fail with "Unable to open a connection to X".
    xwayland-satellite
  ];
}
