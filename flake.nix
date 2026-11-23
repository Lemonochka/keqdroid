{
  description = "keqdroid proxy and VPN client";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      keqdroid = pkgs.callPackage ./nix/package.nix { };
    in
    {
      packages.x86_64-linux = {
        inherit keqdroid;
        default = keqdroid;
      };
      overlays.default = final: prev: {
        keqdroid = final.callPackage ./nix/package.nix { };
      };
    };
}
