{
  description = "Flake for streamlining the creation of QEMU VMs via nix build-vm and systemd";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    test-vm = {
      url = "github:jimurrito/nixos-test-vm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  #
  outputs =
    {
      self,
      nixpkgs,
      test-vm,
      ...
    }:
    {
      #
      nixosModules.default.imports = [
        ./src/options.nix
        ./src/config.nix
      ];
      #
      #
      # TestVM
      nixosConfigurations = {
        # Input test-vm
        test-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # 4gb of ram so it can handle the nested VM
            (import test-vm.baselineConfig {
              cores = 4;
              memorySize = 4096;
            })
            { virtualisation.vmVariant.virtualisation.writableStoreUseTmpfs = false; }
            self.nixosModules.default
            # test config
            (
              { ... }:
              {
                services.quick-qemu = {
                  enable = true;
                  # use the localsource for the VM repo
                  configRepo = ./.;
                  virtualmachines = {
                    nested-vm = {
                      enable = true;
                      portForwarding = {
                        ssh = {
                          vm = 22;
                          host = 2022;
                        };
                        nginx = {
                          vm = 80;
                          host = 8080;
                        };
                      };
                    };
                  };
                };
              }
            )
          ];
        };
        #
        # Nested VM
        nested-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # 4gb of ram so it can handle the nested VM
            (import test-vm.baselineConfig { })
            ({ lib, ... }: {
              networking.hostName = lib.mkOverride 0 "nested-vm";
              users.users.user.password = "test";
              services.openssh = {
                enable = true;
                settings.PasswordAuthentication = true;
              };
              networking.firewall.allowedTCPPorts = [
                22
                80
              ];
              services.nginx = {
                enable = true;
                virtualHosts."_" = {
                  forceSSL = false;
                  enableACME = false;
                  locations."/".extraConfig = ''
                    return 200 "Nginx is running successfully!";
                    add_header Content-Type text/plain;
                  '';
                };
              };
            })
          ];
        };
      };
    };

  #
  #
}
