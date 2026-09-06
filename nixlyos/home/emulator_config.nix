{ lib, ... }:

{
  # Writes 4K-fullscreen configs for every installed emulator on each activation.

  home.activation.emulatorConfigs = lib.hm.dag.entryAfter ["writeBoundary"] ''

    # Dolphin (GameCube / Wii)
    mkdir -p "$HOME/.config/dolphin-emu"

    cat > "$HOME/.config/dolphin-emu/GFX.ini" << 'DOLPHINGFX'
[Settings]
# Auto matches display resolution (4K)
EFBScale = 0
AspectRatio = 0
ShaderCompilationMode = 2
WaitForShadersBeforeStarting = True
MSAA = 0
SSAA = False
ShowFPS = False
LogRenderTimeToFile = False

[Enhancements]
ForceFiltering = True
MaxAnisotropy = 4
ForceTrueColor = True
DisableCopyFilter = True
ArbitraryMipmapDetection = True

[Hacks]
EFBAccessEnable = True
EFBToTextureEnable = True
XFBToTextureEnable = True
EFBScaledCopy = True
SkipDuplicateXFBs = True
ApproximateLogicOp = True

[Hardware]
VSync = True
DOLPHINGFX

    cat > "$HOME/.config/dolphin-emu/Dolphin.ini" << 'DOLPHININI'
[Display]
Fullscreen = True
RenderToMain = True
KeepWindowOnTop = False

[Core]
SkipIdle = True
SyncOnSkipIdle = True
CPUThread = True
GPUDeterminismMode = auto
EmulationSpeed = 1.00
DOLPHININI


    # mGBA (Game Boy / GBC / GBA)
    mkdir -p "$HOME/.config/mgba"

    cat > "$HOME/.config/mgba/config.ini" << 'MGBAINI'
[ports.qt]
fullscreen=1
fpsTarget=60
audioSync=1
videoSync=1
lockAspectRatio=1
volume=256
scaleMultiplier=16
resampleVideo=0
suspendScreensaver=1
pauseOnFocusLost=0
MGBAINI


    # PPSSPP (PSP)
    mkdir -p "$HOME/.config/ppsspp/PSP/SYSTEM"

    cat > "$HOME/.config/ppsspp/PSP/SYSTEM/ppsspp.ini" << 'PPSSPPINI'
[General]
FirstRun = False
AutoRun = True
IgnoreBadMemAccess = True
CheckForNewVersion = False
DiscordRichPresence = False
UISound = False
EnableCheats = False
EnablePlugins = True

[Graphics]
GraphicsBackend = 0 (OPENGL)
UseGeometryShader = False
SkipBufferEffects = False
SoftwareRenderer = False
HardwareTransform = True
SoftwareSkinning = True
TextureFiltering = 1
InternalResolution = 10
HighQualityDepth = 1
FrameSkip = 0
AutoFrameSkip = False
AnisotropyLevel = 4
MultiSampleLevel = 0
FullScreen = True
BufferFiltering = 1
ImmersiveMode = True
ReplaceTextures = True
TexScalingLevel = 1
VSync = True
SplineBezierQuality = 2
ShaderCache = True
UberShaderVertex = True
UberShaderFragment = True
MultiThreading = True
InflightFrames = 3
DisplayCropTo16x9 = True

[Sound]
Enable = True
ExtraAudioBuffering = False
AudioBufferSize = 256
GameVolume = 100

[Control]
HapticFeedback = False
PPSSPPINI


    # PCSX2 (PlayStation 2)
    mkdir -p "$HOME/.config/PCSX2/inis"

    cat > "$HOME/.config/PCSX2/inis/PCSX2.ini" << 'PCSX2INI'
[UI]
StartFullscreen = true
ConfirmShutdown = false

[EmuCore/GS]
upscale_multiplier = 6
MaxAnisotropy = 4
linear_present_mode = 1
TextureFiltering = 2
TriFilter = 1
dithering_ps2 = 2
accurate_blending_unit = 1
texture_preloading = 2
HWDownloadMode = 0
conservative_framebuffer = 1
pcrtc_offsets = 1
pcrtc_antiblur = 1
mipmap_hw = 0
Renderer = -1

[EmuCore/Speedhacks]
EECycleRate = 0
EECycleSkip = 0
fastCDVD = 0
IntcStat = 1
WaitLoop = 1
vuFlagHack = 1
vu1Instant = 1
PCSX2INI


    # Flycast (Dreamcast)
    mkdir -p "$HOME/.config/flycast"

    cat > "$HOME/.config/flycast/emu.cfg" << 'FLYCASTCFG'
[config]
Fullscreen = yes
Section = console

[window]
fullscreen = yes
width = 3840
height = 2160

[pvr]
rend.Resolution = 3840
rend.WideScreen = 0
rend.Clipping = 1
rend.TextureUpscale = 4
rend.MaxFilteredTextureSize = 256
ta.skip = 0
rend.AnisotropicFiltering = 4
rend.PerPixel = 1

[audio]
backend = auto
LimitFPS = 1

[input]
maple_sdl_joystick_0 = 0
FLYCASTCFG


    # Blastem (Genesis / Mega Drive / SMS)
    mkdir -p "$HOME/.config/blastem"

    cat > "$HOME/.config/blastem/blastem.cfg" << 'BLASTEMCFG'
video {
	fullscreen on
	gl on
	vsync on
	scaling linear
	scanlines off
}
BLASTEMCFG


    # Stella (Atari 2600)
    mkdir -p "$HOME/.config/stella"

    cat > "$HOME/.config/stella/stellarc" << 'STELLARC'
fullscreen = 1
vsync = 1
video = opengl
tia.zoom = 8
tia.inter = 0
tia.fsfill = 0
center = 1
sound = 1
volume = 100
joydeadzone = 6
STELLARC


    # Xenia Canary (Xbox 360)
    mkdir -p "$HOME/.config/xenia"

    cat > "$HOME/.config/xenia/xenia-canary.config.toml" << 'XENIACFG'
[Display]
fullscreen = true
present_letterbox = true

[GPU]
draw_resolution_scale_x = 3
draw_resolution_scale_y = 3
gpu = "vulkan"
vsync = true

[GPU.Vulkan]
vulkan_allow_present_mode_mailbox = true
vulkan_allow_present_mode_immediate = false
vulkan_allow_present_mode_fifo_relaxed = true

[HID]
hid = "sdl"

[General]
license_mask = -1

[Canary]
internal_display_resolution = 12
XENIACFG


    # melonDS (Nintendo DS)
    mkdir -p "$HOME/.config/melonDS"

    cat > "$HOME/.config/melonDS/melonDS.toml" << 'MELONDSTOML'
[Instance0]
Window.Fullscreen = true

[3D]
Renderer = 1
GL_ScaleFactor = 8
GL_BetterPolygons = true
GL_HiresCoordinates = true

[Screen]
ScreenLayout = 0
ScreenSizing = 3
IntegerScaling = false
ScreenFilter = true
ScreenAspectTop = 0
ScreenAspectBot = 0

[Audio]
Volume = 256
MELONDSTOML


    # Azahar / Citra (Nintendo 3DS)
    mkdir -p "$HOME/.config/azahar/config"

    cat > "$HOME/.config/azahar/config/qt-config.ini" << 'AZAHARINI'
[Renderer]
use_hw_renderer = true
use_hw_renderer\default = false
use_hw_shader = true
use_hw_shader\default = false
resolution_factor = 4
resolution_factor\default = false
use_shader_jit = true
use_shader_jit\default = false
use_vsync_new = true
use_vsync_new\default = false
texture_filter = 0
texture_filter\default = true

[Layout]
layout_option = 0
layout_option\default = true
fullscreen = true
fullscreen\default = false

[Audio]
output_type = auto
output_type\default = true
volume = 1
AZAHARINI


    # Cemu (Wii U)
    mkdir -p "$HOME/.config/Cemu"

    cat > "$HOME/.config/Cemu/settings.xml" << 'CEMUXML'
<?xml version="1.0" encoding="utf-8"?>
<content>
	<Graphic>
		<api>1</api>
		<VSync>0</VSync>
		<GX2DrawdoneSync>true</GX2DrawdoneSync>
		<UpscaleFilter>1</UpscaleFilter>
		<DownscaleFilter>0</DownscaleFilter>
		<FullscreenScaling>0</FullscreenScaling>
		<AsyncCompile>true</AsyncCompile>
		<Overlay>
			<Position>0</Position>
			<FPS>false</FPS>
		</Overlay>
	</Graphic>
	<Audio>
		<api>0</api>
		<delay>2</delay>
		<TVVolume>100</TVVolume>
		<PadVolume>0</PadVolume>
		<TVChannels>1</TVChannels>
	</Audio>
	<Fullscreen>true</Fullscreen>
</content>
CEMUXML


    # RPCS3 (PlayStation 3)
    mkdir -p "$HOME/.config/rpcs3"

    cat > "$HOME/.config/rpcs3/config.yml" << 'RPCS3YML'
Video:
  Renderer: Vulkan
  Resolution: 1280x720
  Aspect ratio: "16:9"
  Frame limit: Auto
  MSAA: Disabled
  Shader Mode: Async Shader Recompiler
  Write Color Buffers: false
  Write Depth Buffer: false
  Read Color Buffers: false
  Read Depth Buffer: false
  VSync: true
  Stretch To Display Area: false
  Resolution Scale: 300
  Resolution Scale Threshold: 16
  Anisotropic Filter Override: 16
  Shader Precision: High

Audio:
  Renderer: Cubeb
  Audio Format: Automatic
  Master Volume: 100
  Enable Buffering: true
  Desired Audio Buffer Duration: 100

Input/Output:
  Keyboard: "Null"
  Mouse: "Null"
  Camera: "Null"
  Camera type: Unknown
  Move: "Null"
  Buzz emulated controller: "Null"
  Turntable emulated controller: "Null"
  GHLtar emulated controller: "Null"
  Pad handler: SDL

Miscellaneous:
  Start Fullscreen: true
  Exit RPCS3 when process finishes: true
  Automatically start games after boot: true
  Show shader compilation hint: false
RPCS3YML


    # No config written for Ryujinx, Mesen, RMG, xemu or ares: all five
    # auto-detect Xbox pads via SDL2 and generate sane defaults on first launch.

  '';
}
