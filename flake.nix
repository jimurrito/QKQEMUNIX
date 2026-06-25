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
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          qkqemunix-nixops = config.services.quick-qemu;
        in
        with lib;
        {
          #
          #
          # Options for services overlay
          options.services.quick-qemu = with types; {
            default = { };
            enable = mkEnableOption "Quick QEMU VM/Systemd wrapper";
            rootConfigRepo = mkOption {
              type = types.str;
              default = name;
              description = "url repository containing the nixosConfiguration for all the VMs that opt to use it.";
            };
            virtualmachines = mkOption {
              default = { };
              description = "List of VM, in submodule format. Name of submodule should relate to a definition in flake.nix";
              type = types.attrsOf (
                types.submodule (
                  { name, ... }:
                  {
                    options = {
                      #
                      enable = mkEnableOption "This VM service.";
                      useRootConfigRepo = mkEnableOption "Use of the parent repo configured under 'services.quick-qemu'";
                      runAsRoot = mkEnableOption "Run the systemd service as root.";
                      configRepo = mkOption {
                        type = str;
                        default = name;
                        description = "url repository containing the nixosConfiguration for this VM.";
                      };
                      diskPath = mkOption {
                        type = types.str;
                        default = name;
                        description = "Absolute path to the target dir. 'qkqemunix' user should have access to this dir.";
                      };
                      portForwarding = mkOption {
                        default = { };
                        description = "Ports to forward from the VM to the host";
                        type = types.attrsOf (
                          types.submodule (
                            { ... }:
                            {
                              options = {
                                vm = mkOption {
                                  type = types.int;
                                  default = 22;
                                  description = "Port from the VM";
                                };
                                host = mkOption {
                                  type = types.int;
                                  default = 2222;
                                  description = "Port on the host";
                                };
                                protocol = mkOption {
                                  type = types.str;
                                  default = "tcp";
                                  description = "Enables the protcol to be used by the port forward.";
                                };
                                openOnHostFW = mkEnableOption "Opens host port on host's firewall.";
                              };
                            }
                          )
                        );
                      };
                      firewall = {
                        allowedTCPPorts = mkOption {
                          type = types.listOf types.int;
                          default = [ ];
                          description = "Ports that should be opened on the local firewall.";
                        };
                        allowedUDPPorts = mkOption {
                          type = types.listOf types.int;
                          default = [ ];
                          description = "Ports that should be opened on the local firewall.";
                        };
                      };
                    };
                  }
                )
              );
            };
          };
          #
          #
          # config to be implemented via the `options`
          config = mkIf qkqemunix-nixops.enable {
            #
            # enables QEMU
            virtualisation.libvirtd.enable = true;
            # Enables nested virtualization
            boot.extraModprobeConfig = ''
              options kvm_intel nested=1
            '';
            #
            # rootless identity that runs all the VMs
            users = {
              groups.qkqemunix = { };
              users.qkqemunix = {
                enable = true;
                group = "qkqemunix";
                isSystemUser = true;
                createHome = true;
                home = "/var/qkqemunix";
                extraGroups = [ "libvirtd" ];
              };
            };
            #
            # Firewall rules per VM
            networking = mkMerge (
              mapAttrsToList (
                name: conf:
                mkIf (conf.enable) {
                  #  ran if VM is enabled
                  firewall = mkMerge (
                    mapAttrsToList (
                      pname: pconf:
                      mkIf (pconf.openOnHostFW) {
                        #
                        allowedTCPPorts = if (pconf.protocol == "tcp") then [ pconf.host ] else [ ];
                        allowedUDPPorts = if (pconf.protocol == "udp") then [ pconf.host ] else [ ];
                        #
                      }
                    ) conf.portForwarding
                  );
                  #
                }
              ) qkqemunix-nixops.virtualmachines
            );
            #
            # Systemd Service for each VM
            systemd = mkMerge (
              mapAttrsToList (
                name: conf:
                mkIf (conf.enable) {
                  services."qkqemunix-${name}" =
                    let
                      configRepo = if (conf.useRootConfigRepo) then qkqemunix-nixops.rootConfigRepo else conf.configRepo;
                      bash = getExe pkgs.bash;
                    in
                    {
                      enable = conf.enable;
                      description = "QEMU VM wrapper for VM [${name}] running under [qkqemunix]";
                      after = [ "network.target" ];
                      wantedBy = [ "multi-user.target" ];
                      path = with pkgs; [
                        qemu
                        bash
                        nixos-rebuild
                        git
                      ];
                      # Set remote port mapping
                      environment =
                        let
                          #conf.portForward.vmPort;
                          NET_OPTS = mapAttrsToList (
                            _: ports: "hostfwd=tcp::${toString ports.host}-:${toString ports.vm}"
                          ) conf.portForwarding;
                        in
                        {
                          QEMU_NET_OPTS = concatStringsSep "," NET_OPTS;
                        };
                      serviceConfig = {
                        User = if (conf.runAsRoot) then "root" else "qkqemunix";
                        Group = "qkqemunix";
                        Restart = "always";
                        # Set to disk path
                        WorkingDirectory = conf.diskPath;
                        # Start VM via qkqemunix-run
                        ExecStart = ''
                          ${bash} ${./run.bash} ${name} ${configRepo}
                        '';
                      };
                    };
                }
              ) qkqemunix-nixops.virtualmachines
            );
            #
          };
        };
      #
      #
      #
      #
      # TestVM
      nixosConfigurations =
        let
          testConfig =
            { ... }:
            {
              services.quick-qemu = {
                enable = true;
                rootConfigRepo = "git+https://github.com/jimurrito/podmanix";
                virtualmachines = {
                  test-vm = {
                    enable = true;
                    useRootConfigRepo = true;
                    diskPath = "/libvirt/test-vm";
                    portForwarding = {
                      ssh = {
                        vm = 22;
                        host = 2022;
                      };
                      nginx = {
                        vm = 8080;
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
          test-vm = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              # 4gb of ram so it can handle the nested VM
              (import test-vm.baselineConfig { memorySize = 4098; })
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
