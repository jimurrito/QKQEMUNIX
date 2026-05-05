{
  description = "Flake for streamlining the creation of QEMU VMs via nix build-vm and systemd";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  #
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      #lib = nixpkgs.lib;
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "qkqemunix-run";
        meta.mainProgram = "qkqemunix-run";
        version = "0.1.0";
        src = ./.;
        dontBuild = true;
        #
        installPhase = ''
          mkdir -p "$out/bin"
          mv run.bash "$out/bin/qkqemunix-run"
          chmod +x "$out/bin/qkqemunix-run"
        '';
      };
      #
      # <PACKAGE + service via Options>
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          pkgsystem = pkgs.stdenv.hostPlatform.system;
          mainpackage = self.packages.${pkgsystem}.default;
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
                        type = types.listOf (
                          types.submodule (
                            { ... }:
                            {
                              options = {
                                vm = mkOption {
                                  type = types.str;
                                  default = "22";
                                  description = "Port from the VM";
                                };
                                host = mkOption {
                                  type = types.str;
                                  default = "2222";
                                  description = "Port on the host";
                                };
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
          config = lib.mkIf qkqemunix-nixops.enable {
            #
            # Imports package and runs the install steps
            environment.systemPackages = [
              mainpackage
              pkgs.virt-manager
            ];
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
                  firewall = conf.firewall;
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
                          NET_OPTS = mkMerge (
                            mapAttrsToList (ports: "hostfwd=tcp::${ports.hport}-:${ports.vport}") conf.portForwarding
                          );
                        in
                        {
                          QEMU_NET_OPTS = concatStringsSep "," NET_OPTS;
                        };
                      serviceConfig = {
                        User = "qkqemunix";
                        Group = "qkqemunix";
                        # Set to disk path
                        WorkingDirectory = conf.diskPath;
                        # Start VM via qkqemunix-run
                        ExecStart = ''
                          ${getExe mainpackage} ${name} ${configRepo}
                        '';
                        #
                        Restart = "always";
                        #
                      };
                    };
                }
              ) qkqemunix-nixops.virtualmachines
            );
            #
          };
        };
    };
}
