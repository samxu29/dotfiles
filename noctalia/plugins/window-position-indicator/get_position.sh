#!/usr/bin/env bash

focused=$(niri msg -j focused-window 2>/dev/null)
windows=$(niri msg -j windows 2>/dev/null)

wid=$(echo "$focused" | jq -r '.workspace_id')
fid=$(echo "$focused" | jq -r '.id')

if [ -z "$wid" ] || [ "$wid" == "null" ]; then
    echo "0,0"
    exit 0
fi

echo "$windows" | jq -r --argjson wid "$wid" --argjson fid "$fid" '
  map(select(.workspace_id == $wid and .is_floating == false)) | 
  sort_by(.layout.pos_in_scrolling_layout) |
  length as $total | 
  if $total == 0 then
    "0,0"
  else
    (to_entries | map(select(.value.id == $fid))) as $match |
    if ($match | length) > 0 then
      "\($match[0].key + 1),\($total)"
    else
      "0,\($total)"
    end
  end
'
