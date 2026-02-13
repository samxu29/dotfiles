source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

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

