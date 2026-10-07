#!/bin/bash
# Prepares the podcast folder the screensaver plays from.
#
#   prepare-podcast.sh SOURCE OUTPUT
#
# SOURCE holds your originals:
#   episodes/        the episode video files (.mp4 .mov .m4v .mkv), any size
#   ads/ad_1/        one folder per sponsor; the number is its turn in the rotation
#     overlay.png    a transparent PNG, 16:9 (1920x1080), laid over the video
#     sound.m4a      the 5–10 s sponsor sound (.m4a .mp3 .wav .aac); its length
#                    sets how long the overlay stays up (8 s if there is none)
#
# OUTPUT gets web-ready copies (720p H.264, ~2.5 Mbit/s, ready for streaming)
# and manifest.json. Upload the contents of OUTPUT to your web folder with your
# SFTP app and put that folder's https:// address in the screensaver Options.
# Run it again after adding episodes or ads: finished episodes are skipped.
#
# Needs ffmpeg: brew install ffmpeg
set -euo pipefail

SRC="${1:?usage: prepare-podcast.sh SOURCE OUTPUT}"
OUT="${2:?usage: prepare-podcast.sh SOURCE OUTPUT}"
CLIP_SECONDS="${CLIP_SECONDS:-30}"
SHOW_NAME="${SHOW_NAME:-The eFoil Racing Experience}"

command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || {
  echo "ffmpeg is needed: brew install ffmpeg" >&2; exit 1; }

mkdir -p "$OUT/episodes" "$OUT/ads"

json() {   # a JSON string
  local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"
}
seconds() {   # media length in seconds, or null
  local d
  d=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1" 2>/dev/null | head -1)
  [[ "$d" =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo "$d" || echo null
}
slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

shopt -s nullglob nocaseglob
episodes=()
for f in "$SRC"/episodes/*.{mp4,mov,m4v,mkv}; do
  name=$(basename "${f%.*}")
  out="episodes/$(slug "$name").mp4"
  if [[ ! -s "$OUT/$out" || "$f" -nt "$OUT/$out" ]]; then
    echo "Converting $name …"
    ffmpeg -nostdin -loglevel error -y -i "$f" \
      -vf "scale=-2:'min(720,ih)'" -c:v libx264 -preset medium -crf 23 \
      -maxrate 2500k -bufsize 5000k -pix_fmt yuv420p \
      -c:a aac -b:a 128k -ac 2 -movflags +faststart "$OUT/$out.part.mp4"
    mv "$OUT/$out.part.mp4" "$OUT/$out"
  fi
  # "012 - Cascais speed track" → "Cascais speed track"
  title=$(printf '%s' "$name" | sed -E 's/^[0-9]+[ ._-]*//; s/[_]+/ /g')
  episodes+=("{\"file\": $(json "$out"), \"title\": $(json "$title"), \"duration\": $(seconds "$OUT/$out")}")
done
[[ ${#episodes[@]} -gt 0 ]] || { echo "No episodes found in $SRC/episodes" >&2; exit 1; }

ads=()
# ad_1, ad_2, … ad_10 in number order
ad_dirs=()
for dir in "$SRC"/ads/ad_*; do
  n="${dir##*_}"
  [[ -d "$dir" && "$n" =~ ^[0-9]+$ ]] && ad_dirs+=("$n|$dir")
done
sorted=()
if [[ ${#ad_dirs[@]} -gt 0 ]]; then
  while IFS= read -r line; do sorted+=("${line#*|}"); done < <(printf '%s\n' "${ad_dirs[@]}" | sort -t'|' -k1,1n)
fi
for dir in "${sorted[@]+"${sorted[@]}"}"; do
  name=$(basename "$dir")
  mkdir -p "$OUT/ads/$name"
  entry="\"name\": $(json "$name")"
  png=("$dir"/*.png)
  if [[ ${#png[@]} -gt 0 ]]; then
    cp "${png[0]}" "$OUT/ads/$name/overlay.png"
    entry+=", \"image\": $(json "ads/$name/overlay.png")"
  fi
  sound=("$dir"/*.{m4a,mp3,wav,aac})
  if [[ ${#sound[@]} -gt 0 ]]; then
    ext="${sound[0]##*.}"; ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    cp "${sound[0]}" "$OUT/ads/$name/sound.$ext"
    entry+=", \"audio\": $(json "ads/$name/sound.$ext"), \"duration\": $(seconds "$OUT/ads/$name/sound.$ext")"
  fi
  ads+=("{$entry}")
done

join() { local IFS=,; echo "$*"; }
cat > "$OUT/manifest.json" <<JSON
{
  "showName": $(json "$SHOW_NAME"),
  "clipSeconds": $CLIP_SECONDS,
  "skipStartSeconds": 60,
  "skipEndSeconds": 60,
  "adEveryClips": 1,
  "episodes": [$(join "${episodes[@]}")],
  "ads": [$(join "${ads[@]+"${ads[@]}"}")]
}
JSON
echo "Ready: ${#episodes[@]} episodes, ${#ads[@]} ads in $OUT — upload its contents."
