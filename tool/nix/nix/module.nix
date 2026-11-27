{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.programs.keqdroid;
  hasPkexecWrapperOpt = options ? security.polkit.enablePkexecWrapper;
in
{
  options.programs.keqdroid = {
    enable = lib.mkEnableOption "keqdroid proxy and VPN client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = ''
        The keqdroid package to install. Defaults to evaluating the bundled
        binary derivation against the host `pkgs` so no second `nixpkgs`
        instance is pulled in. Can be overridden with
        `inputs.keqdroid.packages.''${pkgs.stdenv.hostPlatform.system}.default`.
      '';
    };

    tun = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable system prerequisites for TUN mode. When enabled, this turns on
          `security.polkit.enable` and defaults
          `security.polkit.enablePkexecWrapper` to `true` so `/run/wrappers/bin/pkexec`
          is available. Set to `false` if you only use Proxy mode and do not
          want polkit enabled. On minimal window managers (Hyprland, Sway,
          Niri, River), also ensure a polkit authentication agent is running.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    security.polkit = lib.mkIf cfg.tun.enable (
      {
        enable = true;
      }
      // lib.optionalAttrs hasPkexecWrapperOpt {
        enablePkexecWrapper = lib.mkDefault true;
      }
    );

    warnings =
      lib.optional (cfg.tun.enable && hasPkexecWrapperOpt && !config.security.polkit.enablePkexecWrapper)
        ''
          programs.keqdroid.tun.enable is true, but security.polkit.enablePkexecWrapper is false.
          TUN mode requires /run/wrappers/bin/pkexec; enable security.polkit.enablePkexecWrapper or set programs.keqdroid.tun.enable = false.
        ''
      ++
        lib.optional
          (
            cfg.tun.enable
            && config.networking.firewall.enable
            && (
              config.networking.firewall.checkReversePath == true
              || config.networking.firewall.checkReversePath == "strict"
            )
          )
          ''
            programs.keqdroid.tun.enable is enabled while networking.firewall.checkReversePath is strict.
            If TUN traffic is dropped by the firewall, set networking.firewall.checkReversePath = "loose".
          '';
  };
}
