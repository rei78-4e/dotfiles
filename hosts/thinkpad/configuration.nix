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
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

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
  services.tailscale.enable = true;

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.udisks2.enable = true;
  services.gvfs.enable = true;

  services.fprintd.enable = true;
  security.pam.services = {
    # GDM runs gdm-fingerprint separately from gdm-password. Enabling
    # pam_fprintd in the shared login stack blocks the password prompt.
    login.fprintAuth = lib.mkForce false;
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

  programs.steam.enable = true;
  hardware.graphics.enable = true;

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
      # Prefer zram for ordinary swapping; keep disk swap for hibernation.
      priority = 10;
    }
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages;

  boot.initrd.systemd.enable = true;

  # 蓋を閉じたら suspend-then-hibernate
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    AllowHibernation = true;
    AllowSuspendThenHibernate = true;
    HibernateDelaySec = "15min";
    HibernateOnACPower = false;
  };

  systemd.services.systemd-hibernate.serviceConfig.ExecStartPre = [
    "${pkgs.systemd}/bin/bootctl set-oneshot @current"
  ];
  systemd.services.systemd-suspend-then-hibernate.serviceConfig.ExecStartPre = [
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
