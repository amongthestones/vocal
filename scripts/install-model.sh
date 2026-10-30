#!/bin/zsh
# Downloads Parakeet Ultra (about 630 MB) into Vocal's folder, once, so the app
# itself never downloads anything. Pinned to one revision of the model repo.
#
# ./scripts/install-model.sh           skips the download if the model is there
# ./scripts/install-model.sh --force   downloads it again
set -euo pipefail

REPO="FluidInference/parakeet-ultra-coreml"
REVISION="95eaa59a39d4394f047a4dc5cce480388a60d1b6"
DEST="$HOME/Library/Application Support/Vocal/Models/parakeet-ultra"

if [[ -d "$DEST/Encoder.mlmodelc" && "${1:-}" != "--force" ]]; then
  echo "Already installed: $DEST (--force to download again)"
  exit 0
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/vocal-model.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Every file in the repo except its own README and git settings.
files=("${(@f)$(curl -fsSL "https://huggingface.co/api/models/$REPO/tree/$REVISION?recursive=1" \
  | /usr/bin/python3 -c 'import json, sys
for item in json.load(sys.stdin):
    if item["type"] == "file" and item["path"] not in ("README.md", ".gitattributes"):
        print(item["path"])')}")

echo "Downloading ${#files} files from $REPO…"
for file in $files; do
  mkdir -p "$work/${file:h}"
  curl -fL --progress-bar -o "$work/$file" "https://huggingface.co/$REPO/resolve/$REVISION/$file"
done

mkdir -p "${DEST:h}"
rm -rf "$DEST"
mv "$work" "$DEST"
trap - EXIT
echo "Installed: $DEST ($(du -sh "$DEST" | cut -f1))"
