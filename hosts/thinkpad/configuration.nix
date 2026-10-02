{
  pkgs,
  inputs,
  lib,
  userName,
  ...
}:
let
  userHome = "/home/${userName}";
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
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "start";
  };

  hardware.enableAllFirmware = true;

  services.tlp.settings = {
    PLATFORM_PROFILE_ON_AC = lib.mkForce "performance";
    CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
    CPU_SCALING_GOVERNOR_ON_AC = "performance";
    CPU_BOOST_ON_AC = 1;
  };

  # Use level 1 on AC power, but keep stronger cooling until the CPU cools
  # down after reaching 80 C. Refresh unchanged levels only for the watchdog.
  boot.extraModprobeConfig = ''
    options thinkpad_acpi fan_control=1
  '';
  systemd.services.thinkpad-ac-fan = {
    description = "Control ThinkPad fan with temperature hysteresis on AC power";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
    };
    script = ''
      set -eu
      fan=/proc/acpi/ibm/fan
      ac=/sys/class/power_supply/AC/online
      read -r fan_control < /sys/module/thinkpad_acpi/parameters/fan_control
      [ "$fan_control" = Y ] || exit 0
      temperature_file=
      for sensor in /sys/class/hwmon/hwmon*; do
        read -r sensor_name < "$sensor/name"
        if [ "$sensor_name" = k10temp ]; then
          temperature_file="$sensor/temp1_input"
          break
        fi
      done
      [ -n "$temperature_file" ] || exit 1
      printf 'watchdog 120\n' > "$fan"
      trap 'printf "level auto\n" > "$fan"' EXIT
      trap 'exit 0' TERM INT
      previous_online=
      refresh_ticks=0
      target_level=1
      while true; do
        read -r online < "$ac"
        if [ "$online" = 1 ]; then
          read -r temperature < "$temperature_file"
          if [ "$temperature" -ge 80000 ]; then
            target_level=7
          elif [ "$temperature" -le 70000 ]; then
            target_level=1
          fi
          reported_level=
          while read -r key value; do
            if [ "$key" = level: ]; then
              reported_level=$value
              break
            fi
          done < "$fan"
          if [ "$previous_online" != 1 ] || [ "$reported_level" != "$target_level" ] || [ "$refresh_ticks" -ge 9 ]; then
            printf 'level %s\n' "$target_level" > "$fan"
            refresh_ticks=0
          else
            refresh_ticks=$((refresh_ticks + 1))
          fi
        elif [ "$previous_online" != 0 ]; then
          printf 'level auto\n' > "$fan"
          target_level=1
        fi
        previous_online=$online
        sleep 10
      done
    '';
  };

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

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

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

  # systemd records the swapfile's current offset in HibernateLocation (EFI).
  # The initrd unlocks the root LUKS device and resumes before mounting ext4.
  # Do not hard-code resume_offset: recreating the swapfile can change it.
  boot.initrd.systemd.enable = true;
  systemd.sleep.settings.Sleep = {
    AllowHibernation = true;
    AllowSuspendThenHibernate = true;
    # If suspend-then-hibernate is requested manually, hibernate after 15 minutes.
    HibernateDelaySec = "15min";
    HibernateOnACPower = false;
  };

  # The persistent boot default may point to another OS. Resume with the same
  # boot entry/kernel that wrote the image, without changing that default.
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

  programs.direnv.enable = true;

  nixpkgs.config.allowUnfree = true;

  users.users.${userName} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
      "kvm"
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
