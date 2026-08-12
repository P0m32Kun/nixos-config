{ config, lib, pkgs, ... }:

{
  # ============ 声音（PipeWire） ============
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # 如需 JACK 应用，取消下面注释
    #jack.enable = true;
  };
}
