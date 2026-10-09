{
  description = "Java 27 dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (pkgs:
        let
          jdk = pkgs.temurin-bin-27;
        in {
          default = pkgs.mkShell {
            packages = [
              jdk
              # (pkgs.gradle.override { java = jdk; })
              # (pkgs.maven.override { jdk_headless = jdk; })
            ];
            JAVA_HOME = jdk.home;
          };
        });
    };
}
