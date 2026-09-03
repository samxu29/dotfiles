# Distrobox shares $HOME. CachyOS fish config does not exist in Ubuntu,
# and ROS 2 needs bash (setup.bash). Switch before sourcing host fish files.
if test -e /run/.containerenv; or test -e /.dockerenv
    exec bash --login
end

source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
function fish_greeting
    fastfetch
    echo "welcome back, $USER"
end

export "MICRO_TRUECOLOR=1"

 #>>> conda initialize >>>
 # !! Contents within this block are managed by 'conda init' !!
 eval /home/samxu/miniconda3/bin/conda "shell.fish" "hook" $argv | source
 # <<< conda initialize <<<

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /home/samxu/miniconda3/bin/conda
    eval /home/samxu/miniconda3/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f "/home/samxu/miniconda3/etc/fish/conf.d/conda.fish"
        . "/home/samxu/miniconda3/etc/fish/conf.d/conda.fish"
    else
        set -x PATH "/home/samxu/miniconda3/bin" $PATH
    end
end
# <<< conda initialize <<<

set -gx XDG_MENU_PREFIX arch-
set -gx MOZ_ENABLE_WAYLAND 1
set -gx LIBVA_DRIVER_NAME radeonsi
set -gx MOZ_DISABLE_RDD_SANDBOX 1
