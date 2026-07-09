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
  #
  # vm mapper
  #vmMapper = vmConfig: logic: (mapAttrsToList (vmName: vmConf: logic) vmConfig);
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
}

#
#
#
#
#
/*
        #
        # Firewall rules per VM
        networking = mkMerge (
          mapAttrsToList (
            name: conf:
            mkIf (vmConf.enable) {
              #  ran if VM is enabled
              firewall = mkMerge (
                mapAttrsToList (
                  pname: pconf:
                  mkIf (pvmConf.openOnHostFW) {
                    #
                    allowedTCPPorts = if (pvmConf.protocol == "tcp") then [ pvmConf.host ] else [ ];
                    allowedUDPPorts = if (pvmConf.protocol == "udp") then [ pvmConf.host ] else [ ];
                    #
                  }
                ) vmConf.portForwarding
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
            mkIf (vmConf.enable) {
              services = {
                # File system creator
                "qkqemunix-diskpath-creator" = {
                  enable = vmConf.enable;
                  description = "Ensures file disk paths exist for qkqemunix VMs";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];
                  path = with pkgs; [ coreutils ];
                  serviceConfig =
                    let
                      mkDir = "${pkgs.coreutils}/bin/mkdir";
                    in
                    {
                      User = if (vmConf.runAsRoot) then "root" else "qkqemunix";
                      Group = "qkqemunix";
                      Restart = "always";
                      # Set to disk path
                      WorkingDirectory = "/libvirt";
                      # Start VM via qkqemunix-run
                      ExecStart = ''
                        ${mkDir} -p ...
                      '';
                    };
                };
                #
                #
                #  VM service(s)
                "qkqemunix-${name}" =
                  let
                    configRepo = if (vmConf.useRootConfigRepo) then qkqemunix-nixops.rootConfigRepo else vmConf.configRepo;
                    bash = getExe pkgs.bash;
                  in
                  {
                    enable = vmConf.enable;
                    description = "QEMU VM wrapper for VM [${name}] running under [qkqemunix]";
                    after = [ "qkqemunix-diskpath-creator.target" ];
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
                        #vmConf.portForward.vmPort;
                        NET_OPTS = mapAttrsToList (
                          _: ports: "hostfwd=tcp::${toString ports.host}-:${toString ports.vm}"
                        ) vmConf.portForwarding;
                      in
                      {
                        QEMU_NET_OPTS = concatStringsSep "," NET_OPTS;
                      };
                    serviceConfig = {
                      User = if (vmConf.runAsRoot) then "root" else "qkqemunix";
                      Group = "qkqemunix";
                      Restart = "always";
                      # Set to disk path
                      WorkingDirectory = vmConf.diskPath;
                      # Start VM via qkqemunix-run
                      ExecStart = ''
                        ${bash} ${./run.bash} ${name} ${configRepo}
                      '';
                    };
                  };
              };
            }
          ) qkqemunix-nixops.virtualmachines
        );
        #
      }
    );
  });
*/
