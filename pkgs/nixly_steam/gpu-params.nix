{
  amd = {
    RADV_PERFTEST = "gpl,nggc,rt";
    AMD_VULKAN_ICD = "RADV";
    mesa_glthread = "true";
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
  };

  nvidia = {
    __GL_THREADED_OPTIMIZATIONS = "1";
    __GL_SHADER_DISK_CACHE = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240";
    __GL_GSYNC_ALLOWED = "1";
    __GL_VRR_ALLOWED = "1";
    PROTON_ENABLE_NVAPI = "1";
    DXVK_ENABLE_NVAPI = "1";
  };

  intel = {
    ANV_ENABLE_PIPELINE_CACHE = "1";
    mesa_glthread = "true";
    MESA_SHADER_CACHE_MAX_SIZE = "10G";
  };

  generic = {
    VKD3D_CONFIG = "dxr,dxr11";
    WINE_FULLSCREEN_FSR = "1";
    PROTON_USE_NTSYNC = "1";
  };
}
