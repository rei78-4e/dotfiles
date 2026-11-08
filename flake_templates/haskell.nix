{
  description = "Haskell dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        # GHCバージョンを固定する場合: pkgs.haskell.packages.ghc98 など
        hpkgs = pkgs.haskellPackages;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            hpkgs.ghc
            hpkgs.cabal-install
            hpkgs.haskell-language-server
            hpkgs.hlint
            hpkgs.fourmolu
            hpkgs.ghcid
            pkgs.zlib # 多くのパッケージのビルドで必要
          ];
        };
      }
    );
}
