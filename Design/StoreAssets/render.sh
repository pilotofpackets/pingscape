#!/bin/zsh
# Renders the App Store header and search results assets with headless Chrome.
# usage: Design/StoreAssets/render.sh [lang ...]   (default: en de fr es it)
# Output: Design/StoreAssets/{header,search}/<lang>.png without alpha channel. App Store Connect
# rejected a JPEG with INVALID_ASSET_FILE_FORMAT, so the JPEG step only drops the alpha channel.
# SAFE=1 renders *-safe.png previews with Apple's art safe area drawn in.
set -e
dir=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
langs=($@)
(( $#langs )) || langs=(en de fr es it)
tmp=$(mktemp -d)
for kind in header search; do
  mkdir -p $dir/$kind
  [[ $kind == header ]] && size=3840,1646 || size=3840,2560
  for lang in $langs; do
    query="kind=$kind&lang=$lang"
    [[ -n $SAFE ]] && query="$query&safe=1"
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --allow-file-access-from-files --virtual-time-budget=3000 --window-size=$size \
      --screenshot=$tmp/shot.png "file://$dir/src/asset.html?$query" 2>/dev/null
    if [[ -n $SAFE ]]; then
      cp $tmp/shot.png $dir/$kind/$lang-safe.png
    else
      sips -s format jpeg -s formatOptions 92 $tmp/shot.png --out $tmp/flat.jpg >/dev/null
      sips -s format png $tmp/flat.jpg --out $dir/$kind/$lang.png >/dev/null
    fi
    echo "$kind/$lang"
  done
done
rm -r $tmp
