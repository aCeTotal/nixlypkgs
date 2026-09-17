{ ... }:

{
  # udisks2 would mount an unscanned stick; only nixly-diskd may.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.udisks2.filesystem-mount" ||
          action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
          action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat") {
        return polkit.Result.NO;
      }
      return polkit.Result.NOT_HANDLED;
    });
  '';
}
