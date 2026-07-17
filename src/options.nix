{ lib, ... }:
with lib;
let
  # creates sub module options for a dynamic option
  mkDynSubmod =
    mod:
    types.attrsOf (
      types.submodule {
        options = mod;
      }
    );
  # creates sub module options for a static option
  mkSubmod =
    mod:
    types.submodule {
      options = mod;
    };
in
{
  #
  # Options for services overlay
  options.services.quick-qemu = {
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
      type = mkDynSubmod {
        enable = mkEnableOption "This VM service.";
        runAsRoot = mkEnableOption "Run the systemd service as root.";
        overrides = mkOption {
          description = "Overrides some of the configurations inherited from the parent module.";
          type = mkSubmod {
            configRepo = mkOption {
              type = types.str;
              default = "";
              description = "overriding url for the repository containing the desired nixosConfiguration.";
            };
            diskPath = mkOption {
              type = types.str;
              default = "";
              description = " Overrides path set in root config. Absolute path to the target dir.";
            };
          };
        };
        subnet = mkOption {
          type = types.str;
          default = "10.0.2.0/24";
          description = "Sets the default subnet range for the VM to be deployed in. Helps avoid conflicts.";
        };
        portForwarding = mkOption {
          description = "Ports to forward from the VM to the host";
          type = mkDynSubmod {
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
        };
      };
    };
  };
}
