{
  description = "Bun + TypeScript + LSP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bun

            # CSS / HTML / JSON LSP
            vscode-langservers-extracted

            # TypeScript / Astro
            nodePackages.typescript
            nodePackages.typescript-language-server

            biome
          ];
        };
      });
    };
}
