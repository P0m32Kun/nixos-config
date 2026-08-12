#!/usr/bin/env bash
# 一键重建系统（在任意目录执行）
set -euo pipefail
sudo nixos-rebuild switch --flake /etc/nixos "$@"
