{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  #
  qkqemunix-nixops = config.services.quick-qemu;
  vms = qkqemunix-nixops.virtualmachines;
  #
  # vm object unwrapper
  vmMapper =
    logic: (mkMerge (mapAttrsToList (vmName: vmConf: (mkIf vmConf.enable (logic vmName vmConf))) vms));
  #
in
{
  config = mkIf qkqemunix-nixops.enable {
    #
    # enables QEMU
    virtualisation.libvirtd.enable = true;
    # Enables nested virtualization
    boot.extraModprobeConfig = ''
      options kvm_intel nested=1
      options kvm_amd nested=1
    '';
    #
    # rootless identity that runs all the VMs
    # Created regardless of if any specific single VM uses it.
    users = {
      groups.qkqemunix = { };
      users.qkqemunix = {
        enable = true;
        group = "qkqemunix";
        isSystemUser = true;
        createHome = true;
        home = "/libvirt";
        extraGroups = [ "libvirtd" ];
      };
    };
    #
    #
    # Firewall rules per VM
    networking = vmMapper (
      _: vmConf: {
        firewall = mkMerge (
          mapAttrsToList (
            _: portConf:
            let
              fwAllow = proto: (if (portConf.protocol == proto) then [ portConf.host ] else [ ]);
            in
            mkIf (portConf.openOnHostFW) {
              allowedTCPPorts = fwAllow "tcp";
              allowedUDPPorts = fwAllow "udp";
            }
          ) vmConf.portForwarding
        );
      }
    );
    #
    #
    # Systemd Service for each VM
    systemd = vmMapper (
      vmName: vmConf: {
        services =
          let
            serviceUser = if (vmConf.runAsRoot) then "root" else "qkqemunix";
            overrideDiskPath = (vmConf.overrides.diskPath != "");
            diskPath =
              if overrideDiskPath then
                vmConf.overrides.diskPath
              else
                "${qkqemunix-nixops.diskPathRoot}/${vmName}";
          in
          {
            #
            #
            # VM diskPath creator
            "qkqemunix-dpc-${vmName}" = {
              enable = vmConf.enable;
              description = "DiskPath creator for qkqemunix VM [${vmName}]";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                User = serviceUser;
                Group = "qkqemunix";
                Type = "oneshot";
                ExecStart = ''
                  ${pkgs.coreutils}/bin/mkdir -p ${diskPath}
                '';
              };
            };
            #
            #
            # VM Service
            "qkqemunix-${vmName}" =
              let
                overrideRepo = vmConf.overrides.configRepo != "";
                configRepo = if overrideRepo then vmConf.overrides.configRepo else qkqemunix-nixops.configRepo;
                # portforwarding firewall config
                qemuNetFWOptions = mapAttrsToList (
                  _: fwds: "hostfwd=${fwds.protocol}::${toString fwds.host}-:${toString fwds.vm}"
                ) vmConf.portForwarding;
                # merge FW config with network subnet config
                qemuNetOptions = qemuNetFWOptions ++ [ "net=${vmConf.subnet}" ];
                # makes script an executable
                runScript = pkgs.runCommand vmName { } ''
                  cp ${./run.bash} $out
                  chmod 0555 $out
                '';
                #
              in
              {
                enable = vmConf.enable;
                description = "QEMU VM wrapper for VM [${vmName}] running under [qkqemunix]";
                after = [ "qkqemunix-dpc-${vmName}.service" ];
                wantedBy = [ "multi-user.target" ];
                path = with pkgs; [
                  qemu
                  bash
                  nixos-rebuild
                  git
                ];
                environment = {
                  QEMU_NET_OPTS = concatStringsSep "," qemuNetOptions;
                  QEMU_KERNEL_PARAMS = "console=ttyS0";
                  QEMU_OPTS = "-device virtio-balloon,free-page-reporting=on";
                };
                serviceConfig = {
                  User = serviceUser;
                  Group = "qkqemunix";
                  Restart = "always";
                  WorkingDirectory = diskPath;
                  ExecStart = ''
                    ${runScript} ${vmName} ${configRepo}
                  '';
                };
              };
          };
      }
    );
    #
  };
}
