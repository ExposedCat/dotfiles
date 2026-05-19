# Catppuccin Mocha (hex without #)
set -l rosewater f5e0dc
set -l flamingo  f2cdcd
set -l pink      f5c2e7
set -l mauve     cba6f7
set -l red       f38ba8
set -l maroon    eba0ac
set -l peach     fab387
set -l yellow    f9e2af
set -l green     a6e3a1
set -l teal      94e2d5
set -l sky       89dceb
set -l sapphire  74c7ec
set -l blue      89b4fa
set -l lavender  b4befe
set -l text      cdd6f4
set -l subtext1  bac2de
set -l subtext0  a6adc8
set -l overlay2  9399b2
set -l overlay1  7f849c
set -l overlay0  6c7086
set -l surface2  585b70
set -l surface1  45475a
set -l surface0  313244
set -l base      1e1e2e
set -l mantle    181825
set -l crust     11111b

# --- Zsh/omz-like highlighting ---
# command name: green if recognized
set -Ux fish_color_command $green

# unknown command / errors: red
set -Ux fish_color_error $red

# arguments/params: blue
set -Ux fish_color_param $blue

# quoted text/strings: yellow
set -Ux fish_color_quote $yellow

# paths that exist: white (text) + underline
set -Ux fish_color_valid_path --underline $text

# operators like | ; & etc
set -Ux fish_color_operator $sky

# redirections > >> < etc
set -Ux fish_color_redirection $pink

# comments (# ...): muted
set -Ux fish_color_comment $overlay1

# autosuggestions (faint): muted
set -Ux fish_color_autosuggestion $surface2

# completions selection highlight
set -Ux fish_color_selection --background=$surface0 $text

# pager (completion menu) colors
set -Ux fish_pager_color_prefix $teal
set -Ux fish_pager_color_completion $text
set -Ux fish_pager_color_description $overlay1
set -Ux fish_pager_color_progress $mauve
