{ pkgs, ... }:
{
  imports = [
    ./desktop.nix
    ./apps/redmine-tracker.nix
  ];

  home.username = "matias";
  home.homeDirectory = "/home/matias";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    fastfetch wl-clipboard ripgrep fd bat eza
    jq htop zip unzip awww tldr alacritty dmenu
    st
  ];

  services.ssh-agent.enable = true;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      IdentityFile = "~/.ssh/matias_ssh";
      AddKeysToAgent = "yes";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Matias Dominguez";
      user.email = "matidomin753@gmail.com";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "flazz";
      plugins = [ "git" "docker" "z" "colored-man-pages" ];
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.tmux = {
    enable = true;
    baseIndex = 1;
    mouse = true;
    historyLimit = 50000;
    terminal = "tmux-256color";
    escapeTime = 0;
    extraConfig = ''
      set-window-option -g xterm-keys on
      bind -n M-h previous-window
      bind -n M-l next-window
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9
    '';
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings.theme = "base16_transparent";
    extraPackages = with pkgs; [ nil nixd ];
  };

}
