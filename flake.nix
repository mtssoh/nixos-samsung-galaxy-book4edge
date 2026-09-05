{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # sudo nixos-rebuild switch --flake ~/nixos#nix-book
      nixosConfigurations.nix-book = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/system ];
      };

      # home-manager switch --flake ~/nixos#matias
      homeConfigurations."matias" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./nix/home ];
      };
    };
}
