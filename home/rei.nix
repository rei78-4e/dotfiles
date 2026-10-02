{
  config,
  pkgs,
  lib,
  inputs,
  standalone ? false,
  ...
}:
{
  imports = [
    ./common_user.nix
  ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      AddKeysToAgent = "yes";
      # Kitty が子プロセスへ設定する light/dark ヒントを SSH 先にも渡す。
      # 接続先の sshd にも AcceptEnv TERM_BACKGROUND が必要。
      SendEnv = [ "TERM_BACKGROUND" ];
    };
  };

  fonts.fontconfig.enable = true;

  # XDG user dirs は freedesktop の仕様。
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = false;
  };

  # herdr is retained in the NixOS closure.
  home.packages = lib.optionals (!standalone) [
    inputs.herdr.packages.${pkgs.system}.default
  ];
}
