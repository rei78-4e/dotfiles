{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    brass-x86_64-linux = {
      url = "tarball+https://github.com/brass-cz/brass/releases/latest/download/brass-x86_64-unknown-linux-gnu.tar.gz";
      flake = false;
    };
    brass-aarch64-linux = {
      url = "tarball+https://github.com/brass-cz/brass/releases/latest/download/brass-aarch64-unknown-linux-gnu.tar.gz";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f s nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (
        system: pkgs: {
          default = pkgs.stdenv.mkDerivation {
            pname = "brass";
            version = "latest";
            src = inputs."brass-${system}"; # 展開済みの bin/ std/ cache/
            nativeBuildInputs = [ pkgs.autoPatchelfHook ];
            buildInputs = [
              pkgs.zlib
              pkgs.zstd
              pkgs.stdenv.cc.cc.lib
            ];
            dontPatchShebangs = true;
            installPhase = "mkdir -p $out && cp -r bin std cache $out/";
          };
        }
      );

      devShells = forAll (
        system: pkgs: {
          default = pkgs.mkShell { packages = [ self.packages.${system}.default ]; };
        }
      );
    };
}
