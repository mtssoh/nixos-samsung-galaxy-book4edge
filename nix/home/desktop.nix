{
  programs.xmobar = {
    enable = true;
    extraConfig = builtins.readFile ../dotfiles/xmobarrc;
  };
}
