{
  pkgs,
  inputs,
  lib,
  userName,
  ...
}:
let
  userHome = "/home/${userName}";
  batteryNotifications = pkgs.writeShellScript "battery-notifications" ''
    battery=/sys/class/power_supply/BAT0
    lowest_bucket=

    while true; do
      if [ -r "$battery/capacity" ] && [ -r "$battery/status" ]; then
        read -r capacity < "$battery/capacity"
        read -r status < "$battery/status"

        if [ "$status" = Discharging ]; then
          # The bucket changes exactly at 90%, 80%, ... 10%.
          bucket=$(( (capacity + 9) / 10 ))
          if [ -n "$lowest_bucket" ] && [ "$bucket" -lt "$lowest_bucket" ]; then
            threshold=$(( bucket * 10 ))
            ${pkgs.libnotify}/bin/notify-send -a Battery -i battery-caution \
              "Battery at $capacity%" "Charge has reached $threshold%."
          fi
          if [ -z "$lowest_bucket" ] || [ "$bucket" -lt "$lowest_bucket" ]; then
            lowest_bucket=$bucket
          fi
        else
          lowest_bucket=
        fi
      fi

      ${pkgs.coreutils}/bin/sleep 15
    done
  '';
  # Resuming from s2idle often wedges this firmware, so never suspend on lid
  # close: stay awake (locked) and hibernate once the lid has been closed on
  # battery for 15 minutes. Short closes while moving resume instantly.
  lidHibernate = pkgs.writeShellScript "lid-hibernate" ''
    closed_for=0

    while true; do
      read -r _ lid < /proc/acpi/button/lid/LID/state
      read -r ac < /sys/class/power_supply/AC/online
      docked=$(${pkgs.systemd}/bin/busctl get-property org.freedesktop.login1 \
        /org/freedesktop/login1 org.freedesktop.login1.Manager Docked)

      if [ "$lid" = closed ] && [ "$ac" = 0 ] && [ "$docked" = "b false" ]; then
        closed_for=$(( closed_for + 5 ))
        if [ "$closed_for" -ge 900 ]; then
          closed_for=0
          ${pkgs.systemd}/bin/systemctl hibernate --check-inhibitors=no || true
        fi
      else
        closed_for=0
      fi

      ${pkgs.coreutils}/bin/sleep 5
    done
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    inputs.nix-hazkey.nixosModules.hazkey
    # ../../modules/thinkpad.nix
  ];

  networking.hostName = "neve";
  environment.etc."dotfiles-host".text = "thinkpad\n";
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
  ];
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };
  # user groups set more under lines

  virtualisation.libvirtd = {
    enable = true;
    onBoot = "start";
  };

  hardware.enableAllFirmware = true;

  systemd.user.services.battery-notifications = {
    description = "Notify on each 10% battery drop";
    wantedBy = [ "graphical-session.target" ];
    unitConfig = {
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    serviceConfig = {
      ExecStart = batteryNotifications;
      Restart = "on-failure";
    };
  };

  # AC: max performance / battery: max battery life.
  # TLP conflicts with power-profiles-daemon (enabled in modules/desktop.nix).
  services.power-profiles-daemon.enable = lib.mkForce false;
  services.tlp = {
    enable = true;
    settings = {
      # CPU (amd-pstate-epp)
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      # ThinkPad firmware profile
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Devices
      PCIE_ASPM_ON_AC = "performance";
      PCIE_ASPM_ON_BAT = "powersupersave";
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      # USB autosuspend on the BT controller and WiFi power save both cause
      # periodic Bluetooth audio dropouts, so keep them running.
      USB_EXCLUDE_BTUSB = 1;
      WIFI_PWR_ON_BAT = "off";

      # Optional: cap charge to reduce battery wear (longevity, not runtime)
      # START_CHARGE_THRESH_BAT0 = 75;
      # STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  services.thinkfan.enable = true;
  # Use level 1 on AC power, but keep stronger cooling until the CPU cools
  # down after reaching 80 C. Refresh unchanged levels only for the watchdog.
  # boot.extraModprobeConfig = ''
  #   options thinkpad_acpi fan_control=1
  # '';
  # systemd.services.thinkpad-ac-fan = {
  #   description = "Control ThinkPad fan with temperature hysteresis on AC power";
  #   wantedBy = [ "multi-user.target" ];
  #   after = [ "systemd-modules-load.service" ];
  #   serviceConfig = {
  #     Type = "simple";
  #     Restart = "on-failure";
  #     RestartSec = 5;
  #   };
  #   script = ''
  #     set -eu
  #     fan=/proc/acpi/ibm/fan
  #     ac=/sys/class/power_supply/AC/online
  #     read -r fan_control < /sys/module/thinkpad_acpi/parameters/fan_control
  #     [ "$fan_control" = Y ] || exit 0
  #     temperature_file=
  #     for sensor in /sys/class/hwmon/hwmon*; do
  #       read -r sensor_name < "$sensor/name"
  #       if [ "$sensor_name" = k10temp ]; then
  #         temperature_file="$sensor/temp1_input"
  #         break
  #       fi
  #     done
  #     [ -n "$temperature_file" ] || exit 1
  #     printf 'watchdog 120\n' > "$fan"
  #     trap 'printf "level auto\n" > "$fan"' EXIT
  #     trap 'exit 0' TERM INT
  #     previous_online=
  #     refresh_ticks=0
  #     target_level=1
  #     while true; do
  #       read -r online < "$ac"
  #       if [ "$online" = 1 ]; then
  #         read -r temperature < "$temperature_file"
  #         if [ "$temperature" -ge 80000 ]; then
  #           target_level=7
  #         elif [ "$temperature" -le 70000 ]; then
  #           target_level=1
  #         fi
  #         reported_level=
  #         while read -r key value; do
  #           if [ "$key" = level: ]; then
  #             reported_level=$value
  #             break
  #           fi
  #         done < "$fan"
  #         if [ "$previous_online" != 1 ] || [ "$reported_level" != "$target_level" ] || [ "$refresh_ticks" -ge 9 ]; then
  #           printf 'level %s\n' "$target_level" > "$fan"
  #           refresh_ticks=0
  #         else
  #           refresh_ticks=$((refresh_ticks + 1))
  #         fi
  #       elif [ "$previous_online" != 0 ]; then
  #         printf 'level auto\n' > "$fan"
  #         target_level=1
  #       fi
  #       previous_online=$online
  #       sleep 10
  #     done
  #   '';
  # };

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [ fcitx5-chewing ];
  };
  services.hazkey.enable = true;
  services.keyd.keyboards.default.ids = lib.mkForce [
    "*"
    "-320f:5055"
  ];
  services.keyd.keyboards.default.settings.main = lib.mkForce {
    leftcontrol = "leftalt";
    leftalt = "leftcontrol";
    rightcontrol = "rightalt";
    rightalt = "rightcontrol";
  };
  # Bluetooth audio stability (VoicePeak/SBC-XQ headphones with mic):
  # - enable-sbc-xq: use SBC-XQ (better S/N) instead of stock SBC for A2DP
  # - enable-msbc + hfp_hf: wideband mic calls instead of narrowband HSP
  # - hfphsp-backend native: use BlueZ instead of ofono, which is not installed
  services.pipewire.wireplumber.extraConfig."51-bluez" = {
    "monitor.bluez.properties" = {
      "bluez5.enable-sbc-xq" = true;
      "bluez5.enable-msbc" = true;
      "bluez5.headset-roles" = [
        "hfp_hf"
        "hsp_hs"
      ];
      "bluez5.hfphsp-backend" = "native";
    };
  };

  services.tailscale.enable = true;

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.udisks2.enable = true;
  services.gvfs.enable = true;

  services.fprintd.enable = true;
  security.pam.services = {
    # pam_fprintd ahead of pam_unix makes the login prompt wait for the
    # sensor before accepting a password, so keep it out of tty logins.
    login.fprintAuth = lib.mkForce false;
    greetd.fprintAuth = false;
    sudo.fprintAuth = true;
    # hyprlock scans the sensor itself over fprintd's DBus API. Leaving
    # pam_fprintd in the stack (fprintAuth defaults to services.fprintd.enable)
    # makes PAM claim the same device concurrently, which breaks both paths.
    hyprlock.fprintAuth = false;
  };

  programs.ssh.extraConfig = ''
    Host eu.nixbuild.net
      PubkeyAcceptedKeyTypes ssh-ed25519
      ServerAliveInterval 60
      ServerAliveCountMax 15
      IdentityFile ${userHome}/.ssh/nixbuild
  '';

  programs.ssh.knownHosts.nixbuild = {
    hostNames = [ "eu.nixbuild.net" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
  };

  # game with steam
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  environment.systemPackages = [ pkgs.protonplus ];
  programs.gamemode.enable = true;

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "eu.nixbuild.net";
      sshUser = "seli";
      system = "x86_64-linux";
      maxJobs = 100;
      supportedFeatures = [
        "benchmark"
        "big-parallel"
      ];
    }
  ];
  nix.settings.builders-use-substitutes = true;
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", \
      ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0a70", \
      MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
  fileSystems."/mnt/bk_disk" = {
    device = "/dev/mapper/bk_disk";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
    ];
  };

  swapDevices = [
    {
      device = "/swapfile";
      # Leave room for the hibernation image as well as ordinary swap use.
      # Apply size changes at boot, before this file becomes active swap.
      size = 16384;
    }
  ];

  # The hibernation image lives in /swapfile on the encrypted root filesystem.
  # Point resume= at the unlocked mapper device, not the inner ext4 UUID from
  # HibernateLocation: that UUID only exists after the LUKS passphrase is
  # entered, and the EFI-variable path times out after 2 minutes. An explicit
  # resume= makes systemd wait indefinitely, so a slow passphrase entry no
  # longer turns a resume into a fresh boot (which looks like a logout).
  boot.resumeDevice = "/dev/mapper/luks-2f10e9ea-8b59-418a-99ad-b4d3812e0d10";

  # zswap instead of zram: when hibernation shrinks memory, zram swaps into RAM
  # itself and image creation fails with -ENOMEM. zswap writes back to the disk swap.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=25"
    # Physical offset of /swapfile's first extent in pages (same unit as
    # resume_offset= and as the HibernateLocation EFI variable). Get it from the
    # first physical_offset (4K blocks) row of `sudo filefrag -v /swapfile`.
    # Recheck if the swapfile is recreated, since the offset moves.
    "resume_offset=55150592"
  ];

  # After a long s2idle the firmware SMI can wedge and an EFI runtime call hangs
  # forever (soft lockup in efi_call_rts). Reboot instead of freezing silently.
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.panic" = 10;
  };

  # BIOS updates (LVFS)
  services.fwupd.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 蓋を閉じたらロックだけ。バッテリーで15分閉じたままなら lid-hibernate が hibernate
  services.logind.settings.Login = {
    HandleLidSwitch = "lock";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.services.lid-hibernate = {
    description = "Hibernate after the lid stays closed on battery";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = lidHibernate;
      Restart = "always";
    };
  };

  # 16G swap に対してカーネル既定の 5.7G では hibernate image が入らず
  # "Normal pages needed > available pages" で -ENOMEM になる
  systemd.tmpfiles.rules = [
    "w /sys/power/image_size - - - - 10737418240"
  ];

  systemd.sleep.settings.Sleep.AllowHibernation = true;

  systemd.services.systemd-hibernate.serviceConfig.ExecStartPre = [
    "${pkgs.systemd}/bin/bootctl set-oneshot @current"
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    webkitgtk_4_1
    gtk3
    glib
  ];

  programs.ssh.startAgent = false;
  services.gnome.gcr-ssh-agent.enable = true;
  systemd.user.services.gcr-ssh-agent.serviceConfig.UnsetEnvironment = [
    "SSH_ASKPASS_REQUIRE"
    "SSH_ASKPASS"
  ];

  nixpkgs.config.allowUnfree = true;

  users.users.${userName} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
      "kvm"
      "wireshark"
    ];
    shell = pkgs.fish;
  };

  programs.zsh.enable = true;
  programs.fish.enable = true;

  environment.etc."crypttab".text = lib.mkForce "";

  system.stateVersion = "24.11";

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  nix.optimise.automatic = true;
}
