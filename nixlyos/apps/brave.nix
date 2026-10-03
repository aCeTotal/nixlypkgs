# Brave: the only browser, stripped to browsing plus Shields.
{ ... }:

{
  environment.etc."brave/policies/managed/lean.json".text = builtins.toJSON {
    BackgroundModeEnabled = false;
    DefaultBrowserSettingEnabled = false;
    MetricsReportingEnabled = false;
    PromotionsEnabled = false;
    BraveAIChatEnabled = false;
    BraveLocalAIEnabled = false;
    BraveNewsDisabled = true;
    BraveP3AEnabled = false;
    BravePlaylistEnabled = false;
    BraveRewardsDisabled = true;
    BraveSpeedreaderEnabled = false;
    BraveStatsPingEnabled = false;
    BraveTalkDisabled = true;
    BraveVPNDisabled = true;
    BraveWalletDisabled = true;
    BraveWaybackMachineEnabled = false;
    BraveWebDiscoveryEnabled = false;
    TorDisabled = true;
  };

  home-manager.sharedModules = [
    {
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = [ "brave-browser.desktop" ];
          "x-scheme-handler/http" = [ "brave-browser.desktop" ];
          "x-scheme-handler/https" = [ "brave-browser.desktop" ];
        };
      };
    }
  ];
}
