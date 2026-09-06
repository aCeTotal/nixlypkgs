{ ... }:

{
  xdg.configFile."wireplumber/wireplumber.conf.d/51-audio-priority.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          { device.name = "alsa_card.pci-0000_00_1f.3" }
        ]
        actions = {
          update-props = {
            api.acp.auto-profile = true
            api.acp.auto-port = true
          }
        }
      }
      {
        matches = [
          { device.name = "alsa_card.pci-0000_04_00.0" }
        ]
        actions = {
          update-props = {
            api.acp.auto-profile = false
            device.profile = "output:hdmi-surround71"
          }
        }
      }
      {
        matches = [
          { node.name = "~alsa_output\\.pci-0000_00_1f\\.3\\..*" }
        ]
        actions = {
          update-props = {
            priority.session = 3000
            priority.driver = 3000
          }
        }
      }
      {
        matches = [
          { node.name = "~alsa_output\\.pci-0000_04_00\\.0\\..*" }
        ]
        actions = {
          update-props = {
            priority.session = 2000
            priority.driver = 2000
          }
        }
      }
    ]

    monitor.bluez.rules = [
      {
        matches = [
          { node.name = "~bluez_output\\..*" }
        ]
        actions = {
          update-props = {
            priority.session = 2500
            priority.driver = 2500
          }
        }
      }
    ]
  '';
}
