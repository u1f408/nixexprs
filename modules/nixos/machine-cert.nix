{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.security.machine-cert;
  opt = options.security.machine-cert;
  isPath = types.path.check;

  enableRootCA = cfg.rootCA.enable && isPath cfg.rootCA.certFile && isPath cfg.rootCA.keyFile;

  commonServiceConfig = {
    Type = "oneshot";
    User = "machine-cert";
    Group = "machine-cert";

    ProtectSystem = "strict";
    PrivateTmp = true;
    ReadWritePaths = [ "/var/lib/machine-cert" ];
    WorkingDirectory = "/var/lib/machine-cert";

    # XXX: these have been copied from the ACME service configuration
    CapabilityBoundingSet = [ "" ];
    DevicePolicy = "closed";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectControlGroups = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RemoveIPC = true;
    RestrictAddressFamilies = "none";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      # 1. allow a reasonable set of syscalls
      "@system-service"
      # 2. and deny unreasonable ones
      "~@privileged @resources"
      # 3. then allow the required subset within denied groups
      "@chown"
    ];
  };

in
{
  options = {
    security.machine-cert = {
      enable = mkEnableOption "machine certificate generation";

      rootCA = {
        enable = mkEnableOption "using a root CA for machine certificate generation";

        certFile = mkOption {
          type = types.either types.str types.path;
          description = "Path to the root CA certificate";
        };

        keyFile = mkOption {
          type = types.either types.str types.path;
          description = "Path to the root CA certificate key";
        };
      };

      useDefaultDomains = mkOption {
        type = types.bool;
        description = "Whether to use the default set of issuance domains";
        default = true;
      };

      extraDomains = mkOption {
        type = types.listOf types.str;
        description = "Extra list of domain names to issue the machine certificate for";
        default = [];
      };
    };
  };

  config = mkIf cfg.enable {
    users.groups.machine-cert = {};
    users.users.machine-cert = {
      home = "/var/lib/machine-cert";
      group = "machine-cert";
      createHome = true;
      isSystemUser = true;
    };

    systemd.services = {
      "machine-cert-fixperms" = 
        let
          script = with builtins; ''
            chown -R 'machine-cert:machine-cert' *
            chmod 750 .

            if [ -d ca ]; then
              chmod 700 ca
              chmod 600 ca/*
            fi

            if [ -d cert ]; then
              chmod 750 cert
              chmod 640 cert/*
            fi
          '';
        in {
          description = "Fix permissions of the machine certificate";
          serviceConfig = commonServiceConfig // {
            RemainAfterExit = true;
            ExecStart = "+" + (pkgs.writeShellScript "machine-cert-fixperms" script);
          };
        };

      "machine-cert-rootca" = mkIf enableRootCA (
        let
          script = with builtins; ''
            # Copy root CA into place
            mkdir -p ca
            cp ${escapeShellArg cfg.rootCA.certFile} ca/cert.pem
            cp ${escapeShellArg cfg.rootCA.keyFile} ca/key.pem

            # Fix permissions on root CA
            chmod 700 ca
            chmod 600 ca/*
          '';
        in {
          description = "Set up machine certificate root CA";
          requires = [ "machine-cert-fixperms.service" ];
          after = [ "machine-cert-fixperms.service" ];

          unitConfig = {
            ConditionPathExists = "!/var/lib/machine-cert/ca/key.pem";
          };

          serviceConfig = commonServiceConfig // {
            RemainAfterExit = true;
            BindReadOnlyPaths = [ cfg.rootCA.certFile cfg.rootCA.keyFile ];
            ExecStart = "+" + (pkgs.writeShellScript "machine-cert-rootca" script);
          };
        });

      "machine-cert-generate" =
        let
          defaultDomains =
            let
              hostnameJoin = hostName: domain: hostName + lib.optionalString (domain != null) ".${domain}";
              machineFqdn = hostnameJoin config.networking.hostName config.networking.domain;
              domainWildcard = domain: [ domain "*.${domain}" ];
            in unique (domainWildcard config.networking.hostName) ++ (domainWildcard machineFqdn);

          domains = (if cfg.useDefaultDomains then defaultDomains else []) ++ cfg.extraDomains;

          script = with builtins; ''
            # Generate certificate
            minica \
              -ca-key ca/key.pem \
              -ca-cert ca/cert.pem \
              -domains ${escapeShellArg (builtins.concatStringsSep "," domains)}

            # Move certificate directory
            mv ${escapeShellArg (head domains)} cert

            # Create files to match structure for ACME certificates
            cp ca/cert.pem cert/chain.pem
            cat cert/cert.pem cert/chain.pem > cert/fullchain.pem
            cat cert/key.pem cert/fullchain.pem > cert/full.pem

            # Fix permissions on base directory
            chown -R 'machine-cert:machine-cert' *

            # Fix permissions on certificate directory
            chmod 750 cert
            chmod 640 cert/*
          '';
        in {
          description = "Generate machine certificate";
          requires = [ "machine-cert-fixperms.service" ] ++ (optional enableRootCA "machine-cert-rootca.service");
          after = [ "machine-cert-fixperms.service" ] ++ (optional enableRootCA "machine-cert-rootca.service");

          path = with pkgs; [ minica ];

          unitConfig = {
            ConditionPathExists = "!/var/lib/machine-cert/cert/key.pem";
          };

          serviceConfig = commonServiceConfig // {
            ExecStart = "+" + (pkgs.writeShellScript "machine-cert-generate" script);
          };
        };
    };

    systemd.targets = {
      "machine-cert-finished" = {
        wantedBy = [ "default.target" ];

        requires = (optional enableRootCA "machine-cert-rootca.service") ++ [
          "machine-cert-generate.service"
          "machine-cert-fixperms.service"
        ];

        after = (optional enableRootCA "machine-cert-rootca.service") ++ [
          "machine-cert-generate.service"
          "machine-cert-fixperms.service"
        ];
      };
    };
  };
}
