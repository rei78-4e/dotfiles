{ pkgs, ... }:
{
  # TERM と違い、任意の環境変数は明示的に許可しないと SSH セッションへ
  # 引き継がれない。Neovim などが端末の light/dark 判定に利用する。
  services.openssh.settings.AcceptEnv = [ "TERM_BACKGROUND" ];

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vim
    neovim
    ripgrep
    fd
    fzf
    eza
    bat
    gh
    nodejs
    zip
    unzip
    python3
    util-linux
  ];

  security.sudo.wheelNeedsPassword = true;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
