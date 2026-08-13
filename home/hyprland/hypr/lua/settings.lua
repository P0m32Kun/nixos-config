hl.config({
  dwindle = {
    preserve_split = true,
    force_split = 2,
  },
})

hl.config({
  master = {
    new_status = "master",
  },
})

hl.config({
  general = {
    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",
  },
})

hl.config({
  input = {
    natural_scroll = true,  -- 鼠标自然滚动（触摸板单独由 touchpad.natural_scroll 控制）
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "",
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,
    repeat_rate = 35,
    repeat_delay = 200,
    touchpad = {
      natural_scroll = true,
    },
  },
})

hl.config({
  cursor = {
    inactive_timeout = 30,
    no_hardware_cursors = true,
  },
})

hl.config({
  misc = {
    force_default_wallpaper = -1,
    disable_hyprland_logo = true,
  },
})

hl.config({
  binds = {
    workspace_back_and_forth = true,
    allow_workspace_cycles = true,
    pass_mouse_when_bound = false,
  },
})
