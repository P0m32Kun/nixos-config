-- 本机（笔记本 eDP-1，3120x2080@120 原生，~256PPI）
-- scale=1.75：Hyprland 会把逻辑尺寸规整到整数像素，实际生效 ≈1.73（3120/1800），
-- 属分数缩放的正常取整行为，启动时会有一次提示，可忽略。
hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "auto",
  scale = "1.75",
})
