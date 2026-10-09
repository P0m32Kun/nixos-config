# ============================================================
# grok-bot：Grok Bot 桌面版（Cursor/xAI 出品的常驻 AI 队友客户端，
# 每个 Bot 有自己的云端电脑；https://cursor.com/download/bot ）
#
# 为什么用 AppImage（同 wechat / zcode / orca 一路）：
#   - 上游 Linux 发 .deb / .rpm / AppImage，AppImage 是 type-2 标准结构，
#     nixpkgs `appimageTools` 直接支持：extractType2 解包 + buildFHSEnv
#     补齐运行库，无需 FUSE / patchelf。
#   - fetchurl 按 URL+hash 锁定，二进制不进 git。
#
# 为什么留 nix（见 docs/decisions/0001）：
#   - GUI 应用 → 留 nix 声明式管理。
#
# Electron 沙箱：官方 desktop 的 Exec 本来就带 --no-sandbox
#   （Exec=AppRun --no-sandbox %U），此处替换 Exec 时原样保留。
#
# URL 注意：路径含上游 commit 段（stable/<commit>/），每次发布都变，
#   无法只由 version 推出，故 version / commit 分开声明；
#   升级用 ./scripts/update.sh grok-bot 一键完成（解析官方下载页）。
#
# 升级流程（新版本发布时）：
#   ./scripts/update.sh grok-bot  # 解析下载页→改 version+commit→重算 hash→nix build 验证
#   sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
final: prev:

let
  inherit (prev) appimageTools;

  version = "0.68.1";
  commit = "33103062f95061ccf9c81c5b365d37ab152c3b66";

  # 下载走 nix-daemon 的代理 env（见 docs/decisions/0002）。
  src = prev.fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/${commit}/linux/x64/Grok_Bot_${version}.AppImage";
    hash = "sha256-L+fFrOzM1VehM7DGGSmX7AwTIPHp/Hvv/MprXozvuls=";
  };

  appimageContents = appimageTools.extractType2 {
    pname = "grok-bot";
    inherit version src;
  };
in
{
  grok-bot = appimageTools.wrapAppImage {
    pname = "grok-bot";
    inherit version;
    # 注意：wrapAppImage 的 src 必须是「解包后的目录」（它内部执行
    # appimage-exec.sh -w <dir>），不是原始 AppImage 文件
    src = appimageContents;

    extraInstallCommands = ''
      # 图标：AppImage 自带 hicolor 全尺寸，整目录搬过来，Icon=grok-bot 即可命中
      mkdir -p $out/share/icons
      cp -r ${appimageContents}/usr/share/icons/hicolor $out/share/icons/

      install -Dm644 ${appimageContents}/grok-bot.desktop \
        $out/share/applications/grok-bot.desktop
      # Exec 指向 FHS wrapper 的可执行名（AppRun → grok-bot），
      # 官方参数 --no-sandbox %U 与 deep-link MimeType 原样保留
      substituteInPlace $out/share/applications/grok-bot.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=grok-bot --no-sandbox %U'
    '';

    meta = {
      description = "Grok Bot — Cursor/xAI 常驻 AI 队友桌面客户端";
      homepage = "https://cursor.com/download/bot";
      # 官方 AppImage 原样取用（非再分发），归类为非自由软件；
      # allowUnfree 已在 modules/packages.nix 打开
      license = prev.lib.licenses.unfreeRedistributable;
      platforms = [ "x86_64-linux" ];
      mainProgram = "grok-bot";
    };
  };
}
