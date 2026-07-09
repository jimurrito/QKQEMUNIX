{ lib, ... }:
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
}
