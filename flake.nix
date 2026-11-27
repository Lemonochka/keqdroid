{
  description = "keqdroid proxy and VPN client";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;
      keqdroid = pkgs.callPackage ./nix/package.nix { };
    in
    {
      packages.${system} = {
        inherit keqdroid;
        default = keqdroid;
      };

      apps.${system} = {
        keqdroid = {
          type = "app";
          program = lib.getExe keqdroid;
          meta = keqdroid.meta;
        };
        default = self.apps.${system}.keqdroid;
      };

      overlays = {
        keqdroid = final: _prev: {
          keqdroid = final.callPackage ./nix/package.nix { };
        };
        default = self.overlays.keqdroid;
      };

      nixosModules = {
        keqdroid = import ./nix/module.nix;
        default = self.nixosModules.keqdroid;
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
