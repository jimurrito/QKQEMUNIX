{ lib, ... }:
with lib;
let
  mkSubmod = mod: types.attrsOf (types.submodule mod);
in
{
  #
  #
  # Options for services overlay
  options.services.quick-qemu = with types; {
    default = { };
    enable = mkEnableOption "Quick QEMU VM/Systemd wrapper";
    configRepo = mkOption {
      type = types.str;
      description = "url to the repository that containing the nixosConfiguration for all the VMs that opt to use it.";
    };
    diskPathRoot = mkOption {
      type = types.str;
      default = "/libvirt";
      description = "Root directory for all VM disks.";
    };
    virtualmachines = mkOption {
      default = { };
      description = "List of VM, in submodule format. Name of submodule should relate to a definition in flake.nix";
      type = mkSubmod (
        { ... }:
        {
          options = {
            enable = mkEnableOption "This VM service.";
            runAsRoot = mkEnableOption "Run the systemd service as root.";
            overrides = mkOption {
              default = {};
              description = "Overrides some of the configurations inherited from the parent module.";
              type = mkSubmod (
                { ... }: {
                  options = {
                    configRepo = mkOption {
                      type = str;
                      default = "";
                      description = "overriding url for the repository containing the desired nixosConfiguration.";
                    };
                    diskPath = mkOption {
                      type = types.str;
                      default = "";
                      description = " Overrides path set in root config. Absolute path to the target dir.";
                    };
                  };
                }
              );
            };
            portForwarding = mkOption {
              default = { };
              description = "Ports to forward from the VM to the host";
              type = mkSubmod (
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
              );
            };
          };
        }
      );
    };
  };
}
