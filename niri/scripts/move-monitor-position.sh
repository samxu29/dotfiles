#!/bin/bash
# Move a monitor's position relative to another monitor (anchor)
# Interactive mode: shows only connected monitors with make/model (e.g. "LG HDR WFHD [DP-10]").
# Usage: move-monitor-position.sh [DISPLAY] [ANCHOR|POSITION] [POSITION]
#   2 args: move-monitor-position.sh DISPLAY POSITION  (anchor = eDP-1)
#   3 args: move-monitor-position.sh DISPLAY ANCHOR POSITION
#   no args: interactive mode
#
# Positions: above, below, left, right, top-left, top-right, bottom-left, bottom-right

CONFIG_DIR="$HOME/.config/niri"
DISPLAY_CONFIG="$CONFIG_DIR/cfg/display.kdl"

ALL_POSITIONS=(above below left right top-left top-right bottom-left bottom-right)

# Get connected display names from niri (only monitors that are currently connected)
get_connected_displays() {
    niri msg -j outputs 2>/dev/null | jq -r 'keys[]' 2>/dev/null
}

# Get human-readable label for display (make + model, or output name if unavailable)
get_display_label() {
    local display="$1"
    local make model
    make=$(niri msg -j outputs 2>/dev/null | jq -r ".[\"$display\"].make // empty")
    model=$(niri msg -j outputs 2>/dev/null | jq -r ".[\"$display\"].model // empty")
    if [ -n "$make" ] && [ -n "$model" ]; then
        echo "$make $model"
    else
        echo "$display"
    fi
}

# Parse "Label [output]" format back to output name
parse_selection_to_output() {
    echo "$1" | sed 's/.*\[\([^]]*\)\]$/\1/'
}

# Check if display is configured in display.kdl
is_configured() {
    grep -q "^output \"$1\"" "$DISPLAY_CONFIG" 2>/dev/null
}

# Get connected displays that are also configured (can be moved)
get_connected_configured_displays() {
    local connected output
    connected=($(get_connected_displays))
    for output in "${connected[@]}"; do
        is_configured "$output" && echo "$output"
    done
}

# Get output block from display.kdl
get_output_block() {
    local display="$1"
    awk -v d="$display" '
        /^output / { in_block = 0; buf = "" }
        $0 ~ "output \"" d "\"" { in_block = 1 }
        in_block { buf = buf $0 "\n" }
        in_block && /^\}/ { print buf; exit }
    ' "$DISPLAY_CONFIG" 2>/dev/null
}

# Parse output block: returns "phys_w phys_h scale x y"
get_output_info() {
    local display="$1"
    local block
    block=$(get_output_block "$display")
    [ -z "$block" ] && return 1
    local mode scale x y w h
    mode=$(echo "$block" | sed -n 's/.*mode "\([^"]*\)".*/\1/p')
    scale=$(echo "$block" | sed -n 's/.*scale \([0-9.]*\).*/\1/p'); scale=${scale:-1}
    x=$(echo "$block" | tr ' ' '\n' | grep '^x=' | head -1 | sed 's/x=//')
    y=$(echo "$block" | tr ' ' '\n' | grep '^y=' | head -1 | sed 's/y=//')
    w=$(echo "$mode" | cut -dx -f1)
    h=$(echo "$mode" | cut -dx -f2 | cut -d@ -f1)
    echo "$w $h $scale $x $y"
}

# Compute position: move_w move_h move_scale anchor_w anchor_h anchor_scale anchor_x anchor_y position
# All dimensions from get_output_info (physical w,h, scale, logical x,y)
compute_position() {
    local mw=$1 mh=$2 mscale=$3 aw=$4 ah=$5 ascale=$6 ax=$7 ay=$8 pos=$9
    # Logical dimensions (niri uses logical coords)
    local mlw mlh alw alh
    mlw=$(awk "BEGIN {printf \"%.0f\", $mw / $mscale}")
    mlh=$(awk "BEGIN {printf \"%.0f\", $mh / $mscale}")
    alw=$(awk "BEGIN {printf \"%.0f\", $aw / $ascale}")
    alh=$(awk "BEGIN {printf \"%.0f\", $ah / $ascale}")
    local x y
    case "$pos" in
        above)
            x=$(awk "BEGIN {printf \"%.0f\", $ax + ($alw - $mlw) / 2}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay - $mlh}")
            ;;
        below)
            x=$(awk "BEGIN {printf \"%.0f\", $ax + ($alw - $mlw) / 2}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay + $alh}")
            ;;
        left)
            x=$(awk "BEGIN {printf \"%.0f\", $ax - $mlw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay + ($alh - $mlh) / 2}")
            ;;
        right)
            x=$(awk "BEGIN {printf \"%.0f\", $ax + $alw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay + ($alh - $mlh) / 2}")
            ;;
        top-left)
            x=$(awk "BEGIN {printf \"%.0f\", $ax - $mlw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay - $mlh}")
            ;;
        top-right)
            x=$(awk "BEGIN {printf \"%.0f\", $ax + $alw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay - $mlh}")
            ;;
        bottom-left)
            x=$(awk "BEGIN {printf \"%.0f\", $ax - $mlw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay + $alh}")
            ;;
        bottom-right)
            x=$(awk "BEGIN {printf \"%.0f\", $ax + $alw}")
            y=$(awk "BEGIN {printf \"%.0f\", $ay + $alh}")
            ;;
        *) echo "Invalid position: $pos" >&2; return 1 ;;
    esac
    echo "${x%.*} ${y%.*}"
}

# Update position line for display in display.kdl
update_position() {
    local display="$1" x="$2" y="$3"
    local tmp
    tmp=$(mktemp)
    awk -v d="$display" -v x="$x" -v y="$y" '
        /^output / { in_block = 0 }
        $0 ~ "output \"" d "\"" { in_block = 1 }
        in_block && /position x=/ {
            sub(/x=[0-9-]+/, "x=" x)
            sub(/y=[0-9-]+/, "y=" y)
        }
        { print }
    ' "$DISPLAY_CONFIG" > "$tmp" && mv "$tmp" "$DISPLAY_CONFIG"
}

# Interactive mode
interactive_mode() {
    local outputs
    outputs=($(get_connected_configured_displays))
    if [ ${#outputs[@]} -eq 0 ]; then
        echo "No connected displays found (run within niri; new displays need auto-configure first)"
        exit 1
    fi

    # Build "Label [output]" for each connected display
    local display_opts=()
    for o in "${outputs[@]}"; do
        display_opts+=("$(get_display_label "$o") [$o]")
    done

    local display_sel display
    if command -v fzf &>/dev/null; then
        display_sel=$(printf '%s\n' "${display_opts[@]}" | fzf --prompt="Monitor to move: ")
    else
        echo "Monitor to move:"
        select display_sel in "${display_opts[@]}"; do
            [ -n "$display_sel" ] && break
        done
    fi
    [ -z "$display_sel" ] && exit 1
    display=$(parse_selection_to_output "$display_sel")

    local anchor_opts=()
    for o in "${outputs[@]}"; do
        [ "$o" != "$display" ] && anchor_opts+=("$(get_display_label "$o") [$o]")
    done
    if [ ${#anchor_opts[@]} -eq 0 ]; then
        echo "Only one display connected; need at least two."
        exit 1
    fi

    local anchor_sel anchor
    if command -v fzf &>/dev/null; then
        anchor_sel=$(printf '%s\n' "${anchor_opts[@]}" | fzf --prompt="Relative to (anchor): ")
    else
        echo "Position relative to:"
        select anchor_sel in "${anchor_opts[@]}"; do
            [ -n "$anchor_sel" ] && break
        done
    fi
    [ -z "$anchor_sel" ] && exit 1
    anchor=$(parse_selection_to_output "$anchor_sel")

    local position
    if command -v fzf &>/dev/null; then
        position=$(printf '%s\n' "${ALL_POSITIONS[@]}" | fzf --prompt="Position ($(get_display_label "$anchor")): ")
    else
        echo "Position relative to $(get_display_label "$anchor"):"
        select position in "${ALL_POSITIONS[@]}"; do
            [ -n "$position" ] && break
        done
    fi
    [ -z "$position" ] && exit 1

    move_display "$display" "$anchor" "$position"
}

# move_display DISPLAY ANCHOR POSITION
move_display() {
    local display="$1" anchor="$2" position="$3"
    local minfo ainfo
    minfo=$(get_output_info "$display") || { echo "Error: Display $display not found"; exit 1; }
    ainfo=$(get_output_info "$anchor") || { echo "Error: Anchor $anchor not found"; exit 1; }

    local mw mh mscale mx my aw ah ascale ax ay
    read -r mw mh mscale mx my <<< "$minfo"
    read -r aw ah ascale ax ay <<< "$ainfo"

    local xy
    xy=($(compute_position "$mw" "$mh" "$mscale" "$aw" "$ah" "$ascale" "$ax" "$ay" "$position"))
    local x=${xy[0]} y=${xy[1]}

    update_position "$display" "$x" "$y"
    niri msg action load-config-file

    echo "✓ Moved $display to $position of $anchor (position: x=$x y=$y)"
}

case "${1:-}" in
    "")
        interactive_mode
        ;;
    --help|-h)
        echo "Usage: $0 [DISPLAY] [ANCHOR|POSITION] [POSITION]"
        echo ""
        echo "Move a monitor relative to an anchor monitor."
        echo "Interactive mode shows only connected monitors by make/model."
        echo ""
        echo "  (no args)   Interactive: select monitor, anchor, position (connected only)"
        echo "  2 args      DISPLAY POSITION  (anchor defaults to eDP-1)"
        echo "  3 args      DISPLAY ANCHOR POSITION"
        echo ""
        echo "Positions: above, below, left, right, top-left, top-right, bottom-left, bottom-right"
        echo ""
        echo "Examples:"
        echo "  $0                              # Interactive (works with any monitor)"
        echo "  $0 HDMI-1 left                  # Move HDMI-1 left of eDP-1"
        echo "  $0 DP-2 eDP-1 top-right         # Move DP-2 to top-right of eDP-1"
        echo "  $0 DP-3 HDMI-1 below            # Move DP-3 below HDMI-1"
        ;;
    *)
        if [ -n "${3:-}" ]; then
            move_display "$1" "$2" "$3"
        elif [ -n "${2:-}" ]; then
            # 2 args: DISPLAY POSITION, anchor = eDP-1
            move_display "$1" "eDP-1" "$2"
        else
            echo "Error: Need POSITION (and optionally ANCHOR)"
            exit 1
        fi
        ;;
esac

