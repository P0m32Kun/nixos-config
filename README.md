# NixOS 配置仓库

使用 **flake** 管理 NixOS 配置，配置托管在 **GitHub**，国内使用 **清华 TUNA 镜像**。

## 目录结构

```
nixos-config/
├── flake.nix              # flake 入口（nixpkgs 来源、主机定义）
├── flake.lock             # 版本锁定（提交到 GitHub，保证可复现）
├── configuration.nix      # 主机主要配置（含国内镜像设置）
├── hardware-configuration.nix  # 硬件配置（nixos-generate-config 生成，勿手改）
├── modules/               # （可选）按功能拆分的模块
├── hosts/                 # （可选）多主机时放各主机配置
└── rebuild.sh             # 一键重建脚本
```

## 国内镜像说明

- **nixpkgs 源**：`flake.nix` 中直接使用 TUNA 的 channel tarball
  `https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixos-26.05/nixexprs.tar.xz`
- **二进制缓存**：`configuration.nix` 的 `nix.settings.substituters` 优先 TUNA，官方兜底

> 想换中科大 USTC？把 flake.nix 中的 URL 前缀换成 `https://mirrors.ustc.edu.cn/nix-channels/`，并把 `substituters` 第一条改为 `https://mirrors.ustc.edu.cn/nix-channels/store`。

## 日常使用

```bash
# 本机重建/升级
sudo nixos-rebuild switch --flake /etc/nixos

# 更新 nixpkgs 到镜像最新版本（在配置目录里执行）
cd /etc/nixos && nix flake update nixpkgs
sudo nixos-rebuild switch --flake /etc/nixos

# 添加新软件：编辑 configuration.nix 的 environment.systemPackages
# 然后执行上面第一条命令

# 安装后查看生成结果（不生效，用于测试）
sudo nixos-rebuild build --flake /etc/nixos

# 回滚到上一个版本
sudo nixos-rebuild switch --rollback
```

## 首次上传 GitHub（只做一次）

1. 在 [github.com](https://github.com/new) 新建一个仓库（例如 `nixos-config`，Public/Private 均可）
2. 把生成的 SSH 公钥添加到 GitHub：Settings → SSH and GPG keys → New SSH key
   （公钥内容：`cat ~/.ssh/id_ed25519.pub`）
3. 关联远程仓库并推送：

```bash
cd ~/nixos-config
git remote add origin git@github.com:你的用户名/nixos-config.git
git push -u origin main
```

4. 之后每次改配置：

```bash
cd ~/nixos-config
git add -A && git commit -m "描述你的改动"
git push
# 然后在需要应用的机器上
sudo nixos-rebuild switch --flake /etc/nixos
```

## 在新机器上恢复这套配置

```bash
git clone git@github.com:你的用户名/nixos-config.git /etc/nixos
# 重新生成该机器的 hardware-configuration.nix
nixos-generate-config --root /mnt  # 新装系统时
# 或在本机直接
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
sudo nixos-rebuild switch --flake /etc/nixos
```
