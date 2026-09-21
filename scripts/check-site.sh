#!/bin/bash
# Fails while the website still has placeholders (the legal notice needs the
# owner's real address and email). Run by the Pages workflow before it deploys.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${SKIP_TODO_CHECK:-}" ] && grep -rn "TODO" site --include='*.html'; then
  echo "site/ still contains TODO placeholders. Fill in the legal notice first." >&2
  exit 1
fi
# Every local link and image must exist.
status=0
while IFS= read -r file; do
  dir=$(dirname "$file")
  for target in $(grep -oE '(href|src)="[^"#:]+"' "$file" | sed -E 's/^(href|src)="//; s/"$//'); do
    case "$target" in
      /*) path="site$target" ;;
      *) path="$dir/$target" ;;
    esac
    [ -d "$path" ] && path="$path/index.html"
    [ -e "$path" ] || { echo "$file: missing $target" >&2; status=1; }
  done
done < <(find site -name '*.html')
exit $status
