{
  description = "dotfiles: NixOS + flakes + Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-hazkey = {
      url = "github:aster-void/nix-hazkey/4f791a241963f6804420d69613c25c6d25610e73";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jolt = {
      url = "github:jordond/jolt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr = {
      url = "github:ogulcancelik/herdr/v0.7.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zathura-gui = {
      url = "github:Uliboooo/zathura_thin_gui_wrapper";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-float-sticky = {
      url = "github:probeldev/niri-float-sticky";
    };

    niri-scratchpad = {
      url = "github:argosnothing/niri-scratchpad-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-window-hooks = {
      url = "github:rei78-4e/niri-window-hooks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:charmbracelet/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helix-git = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      linuxSystem = "x86_64-linux";
      userNames = {
        desktop = "rei";
        thinkpad = "rei";
        standalone = "rei";
      };

      gitSigningKeys = {
        desktop = "B89051A56543D9A9781C02CFCC8659005EEB10EA";
        thinkpad = "B89051A56543D9A9781C02CFCC8659005EEB10EA";
      };

      mkGitSigningConfig = signingKey: {
        xdg.configFile."git-signing.conf".text = ''
          [user]
            signingkey = ${signingKey}
        '';
      };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      mkHome =
        system: signingKey: userName:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          modules = [
            ./home/rei.nix
            (mkGitSigningConfig signingKey)
          ];
          extraSpecialArgs = {
            inherit inputs userName;
            standalone = true;
          };
        };
    in
    {
      devShells.${linuxSystem}.default =
        let
          pkgs = mkPkgs linuxSystem;
        in
        pkgs.mkShell {
          packages = with pkgs; [
            lua-language-server
            tombi
            biome
            nixfmt
            stylua
            shfmt
          ];
        };

      # ===== Home Manager (standalone) =====
      homeConfigurations = {
        ${userNames.standalone} = mkHome linuxSystem gitSigningKeys.desktop userNames.standalone;
        "${userNames.standalone}@${linuxSystem}" =
          mkHome linuxSystem gitSigningKeys.desktop
            userNames.standalone;
      };

      lib = {
        userName = userNames.standalone;
        inherit userNames;
      };

      # ===== NixOS (desktop) =====
      nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {
          inherit inputs;
          userName = userNames.thinkpad;
        };
        modules = [
          ./hosts/thinkpad/configuration.nix

          (
            {
              pkgs,
              ...
            }:
            {
              environment.systemPackages = with pkgs; [
                bash
              ];
              environment.pathsToLink = [ "/bin" ];
            }
          )

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = {
              inherit inputs;
              userName = userNames.thinkpad;
              standalone = false;
            };
            home-manager.sharedModules = [ (mkGitSigningConfig gitSigningKeys.thinkpad) ];
            home-manager.users.${userNames.thinkpad} = import ./home/rei.nix;
          }
        ];
      };

      nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {
          inherit inputs;
          userName = userNames.desktop;
        };
        modules = [
          ./hosts/desktop/configuration.nix

          (
            {
              pkgs,
              ...
            }:
            {
              environment.systemPackages = with pkgs; [
                bash
              ];
              environment.pathsToLink = [ "/bin" ];
            }
          )

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = {
              inherit inputs;
              userName = userNames.desktop;
              standalone = false;
            };
            home-manager.sharedModules = [ (mkGitSigningConfig gitSigningKeys.desktop) ];
            home-manager.users.${userNames.desktop} = import ./home/rei.nix;
          }

          # inputs.shojiwm.nixosModules.default
          # {
          #   programs.shojiwm = {
          #     enable = true;
          #     initConfig = {
          #       enable = true;
          #       users = [ "seli" ];
          #     };
          #   };
          # }
        ];
      };
    };
}
