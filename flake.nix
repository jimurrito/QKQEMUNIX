{
  description = "<PROJECT DESCRIPTION>";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  #
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "<PACKAGE NAME>";
        meta.mainProgram = "<PACKAGE NAME>";
        version = "0.1.0";
        src = ./.;
        dontBuild = true;
        #
        installPhase = ''
          #
          # <Example>
          #
          moduleDir="$out/module"
          mkdir -p "$moduleDir"
          cp IonUpdate.ps1 IonUpdate.psd1 IonUpdate.psm1 "$moduleDir/"
          mkdir -p "$out/bin"
          cat > "$out/bin/ion-update" << EOF
          #!/usr/bin/env bash
          export PSModulePath="$moduleDir:\$PSModulePath"
          ${lib.getExe pkgs.powershell} -NonInteractive -Command "$moduleDir/IonUpdate.ps1 \$@"
          EOF
          chmod +x "$out/bin/ion-update"
        '';
      };
      #
      # <Just package>
      nixosModules.package =
        {
          pkgs,
          ...
        }:
        let
          pkgsystem = pkgs.stdenv.hostPlatform.system;
          mainpackage = self.packages.${pkgsystem}.default;
        in
        {
          # config to be implemented via the `options`
          config.environment.systemPackages = [
            mainpackage
          ];
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
          <PACKAGE NAME>-nixops = config.services.<PACKAGE NAME>;
        in
        {
          # Options for services overlay
          options.services.<PACKAGE NAME> = with lib; {
            enable = mkEnableOption "IonUpdate scheduled service";
            example = mkOption {
              type = types.str;
              default = "<Option default>";
              description = "<Option Description>";
            };
          };
          #
          # config to be implemented via the `options`
          config = lib.mkIf <PACKAGE NAME>-nixops.enable {
            # Imports package and runs the install steps
            environment.systemPackages = [
              mainpackage
            ];
            # rootless identity
            users = {
              groups.<PACKAGE NAME> = { };
              users.<PACKAGE NAME> = {
                enable = true;
                group = "<PACKAGE NAME>";
                isSystemUser = true;
              };
            };
            # systemd service
            systemd = {
              services.<PACKAGE NAME> = {
                description = "<PACKAGE NAME> service";
                path = with pkgs; [
                  powershell
                ];
                serviceConfig = with lib; {
                  Type = "oneshot";
                  User = "<PACKAGE NAME>";
                  Group = "<PACKAGE NAME>";
                  ExecStart = ''
                    ${getExe mainpackage} <PACKAGE ARGS 4 Service>
                  '';
                };
              };
              timers.<PACKAGE NAME> = {
                description = "<PACKAGE NAME> timer";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnCalendar = <PACKAGE NAME>-nixops.interval;
                  Persistent = true;
                };
              };
            };
          };
        };
    };
}
