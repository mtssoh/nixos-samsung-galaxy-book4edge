{ pkgs, ... }:
let
  jdk21-fx = pkgs.jdk21.override {
    enableJavaFX = true;
    openjfx21 = pkgs.openjfx21.override { withWebKit = true; };
  };
  redmine-tracker = pkgs.writeShellScriptBin "redmine-tracker" ''
    exec ${jdk21-fx}/bin/java -jar "$HOME/opt/redmine-time-tracker.jar" "$@"
  '';
in
{
  home.packages = [ redmine-tracker ];

  xdg.desktopEntries.redmine-tracker = {
    name = "Redmine Time Tracker";
    exec = "redmine-tracker";
    icon = "utilities-terminal";
    comment = "Time tracking para Redmine";
    categories = [ "Office" "ProjectManagement" ];
    terminal = false;
    type = "Application";
  };
}
