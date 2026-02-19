#!/bin/bash
# Move all workspaces to a chosen monitor (preserves order)
# Usage: move-all-workspaces-to-monitor.sh [OUTPUT]
#   no args:   Interactive - select target monitor
#   1 arg:     OUTPUT   Move all workspaces to OUTPUT

CONFIG_DIR="$HOME/.config/niri"
DISPLAY_CONFIG="$CONFIG_DIR/cfg/display.kdl"

# Get connected display names from niri
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

# Get connected displays that are also configured
get_connected_configured_displays() {
    local output
    for output in $(get_connected_displays); do
        is_configured "$output" && echo "$output"
    done
}

# Interactive: move all workspaces to chosen monitor
interactive_select_target() {
    local outputs=()
    while IFS= read -r o; do outputs+=("$o"); done < <(get_connected_configured_displays)
    if [ ${#outputs[@]} -eq 0 ]; then
        echo "No connected displays found"
        exit 1
    fi

    local target_opts=()
    for o in "${outputs[@]}"; do
        target_opts+=("$(get_display_label "$o") [$o]")
    done

    local target_sel
    if command -v fzf &>/dev/null; then
        target_sel=$(printf '%s\n' "${target_opts[@]}" | fzf --prompt="Move ALL workspaces to monitor: ")
    else
        echo "Move ALL workspaces to monitor:"
        select target_sel in "${target_opts[@]}"; do
            [ -n "$target_sel" ] && break
        done
    fi
    [ -z "$target_sel" ] && exit 1

    parse_selection_to_output "$target_sel"
}

# Move all workspaces to target, preserving order (by output, then idx)
# - Focus target monitor, then its last (empty) workspace — park there so we never move focused
# - For each source: repeatedly move workspace at idx 1 (the first). After each move, the next
#   becomes idx 1. The last workspace on each monitor is always empty (niri), so we stop before it.
#   This preserves order and avoids idx-tracking race conditions.
move_all_to_monitor() {
    local target="$1"
    local count=0

    local active_id
    active_id=$(niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.is_active == true) | .id' | head -1)
    niri msg action focus-monitor "$target"
    sleep 0.1
    local last_idx
    last_idx=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" '[.[] | select(.output == $t) | .idx] | max')
    if [ -n "$last_idx" ] && [ "$last_idx" != "null" ]; then
        niri msg action focus-workspace "$last_idx"
        sleep 0.1
    fi

    local sources
    sources=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" '
        [.[] | select(.output != $t) | .output] | unique | sort | .[]
    ')

    for source in $sources; do
        local n
        n=$(niri msg -j workspaces 2>/dev/null | jq -r --arg s "$source" '[.[] | select(.output == $s)] | length')
        local to_move=$((n - 1))
        local desired_order
        desired_order=$(niri msg -j workspaces 2>/dev/null | jq -r --arg s "$source" '
            [.[] | select(.output == $s)] | sort_by(.idx) | (.[:-1] | .[].id)
        ')
        local i
        for i in $(seq 1 "$to_move"); do
            niri msg action focus-monitor "$source"
            sleep 0.15
            niri msg action focus-workspace 1
            sleep 0.08
            niri msg action move-workspace-to-monitor "$target"
            count=$((count + 1))
            sleep 0.05
        done
        if [ -n "$active_id" ] && [ "$active_id" != "null" ]; then
            local desired_idx actual_idx
            desired_idx=$(echo "$desired_order" | grep -n "^${active_id}$" | cut -d: -f1)
            actual_idx=$(niri msg -j workspaces 2>/dev/null | jq -r --arg t "$target" --argjson wid "$active_id" '
                [.[] | select(.output == $t)] | sort_by(.idx) |
                to_entries[] | select(.value.id == $wid) | (.key + 1)
            ')
            if [ -n "$desired_idx" ] && [ -n "$actual_idx" ] && [ "$desired_idx" != "$actual_idx" ]; then
                local moves=$((desired_idx - actual_idx))
                niri msg action focus-monitor "$target"
                sleep 0.08
                niri msg action focus-workspace "$actual_idx"
                sleep 0.05
                local j
                if [ "$moves" -gt 0 ]; then
                    for j in $(seq 1 "$moves"); do
                        niri msg action move-workspace-down
                        sleep 0.05
                    done
                else
                    for j in $(seq 1 "$((-moves))"); do
                        niri msg action move-workspace-up
                        sleep 0.05
                    done
                fi
            fi
        fi
    done

    [ $count -gt 0 ] && niri msg action focus-monitor "$target"

    echo "✓ Moved $count workspace(s) to $target (order preserved)"
}

case "${1:-}" in
    "")
        target=$(interactive_select_target)
        [ -n "$target" ] && move_all_to_monitor "$target"
        ;;
    --help|-h)
        echo "Usage: $0 [OUTPUT]"
        echo ""
        echo "Move all workspaces to a monitor (preserves order)."
        echo ""
        echo "  (no args)   Interactive: select target monitor"
        echo "  1 arg       OUTPUT   Move all workspaces to OUTPUT"
        echo ""
        echo "Examples:"
        echo "  $0              # Interactive: select target"
        echo "  $0 eDP-1        # Move all workspaces to eDP-1"
        ;;
    *)
        move_all_to_monitor "$1"
        ;;
esac
