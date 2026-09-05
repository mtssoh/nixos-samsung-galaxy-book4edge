{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./x1e.nix
  ];

  time.timeZone = "America/Asuncion";

  networking = {
    hostName = "nix-book";
    firewall.enable = false;
    networkmanager.enable = true;
  };

  users.users.matias = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  fileSystems."/home" = {
    device = "/dev/disk/by-label/home";
    fsType = "ext4";
  };

  swapDevices = [{
    device = "/home/swapfile";
    size = 8 * 1024;
  }];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  nix.optimise.automatic = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  programs.niri.enable = true;

  services.xserver = {
    enable = true;
    displayManager.startx = {
      enable = true;
      generateScript = true;
    };

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      config = builtins.readFile ../dotfiles/xmonad.hs;
    };

    libinput.naturalScrolling = true;      
  };

  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono ];

  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";
    packages = [ pkgs.terminus_font ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      Experimental = true;
      FastConnectable = true;
    };
  };

  services = {
    openssh.enable = true;
    tailscale.enable = true;
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git helix curl wget firefox xwayland-satellite
    ps_mem brightnessctl podman-compose awscli2
    claude-code dnslookup xterm
  ];

  system.stateVersion = "26.05";
}
