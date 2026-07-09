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
      nixosConfigurations =
        let
          testConfig =
            { ... }:
            {
              #
              services.quick-qemu = {
                enable = true;
                configRepo = "git+https://github.com/jimurrito/nixos-test-vm";
                virtualmachines = {
                  test-vm = {
                    enable = true;
                    portForwarding = {
                      ssh = {
                        vm = 22;
                        host = 2022;
                      };
                      nginx = {
                        vm = 80;
                        host = 8080;
                        openOnHostFW = true;
                      };
                    };
                  };
                };
              };
            };
        in
        {
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
              # test config
              self.nixosModules.default
              testConfig
            ];
          };
        };
    };

  #
  #
}
