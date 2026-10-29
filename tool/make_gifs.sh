#!/bin/sh
# Renders the README's demos with the example app on macOS (Impeller, the
# shaders as they really run) and turns them into doc/*.gif with ffmpeg.
# Run from the package's root:
#   sh tool/make_gifs.sh                   # the pairs below
#   PAIRS="Neon:Arabic" sh tool/make_gifs.sh
#   RENDER=0 sh tool/make_gifs.sh          # again from frames already rendered
set -e
PAIRS=${PAIRS:-"Neon:Latin,Ribbon:Latin,Dew:Latin,Ivy:Latin,Jelly:Latin,Ink bleed:Japanese,Weld:Japanese,Frost:Japanese,Sakura:Japanese,Snow:Japanese,Plain ink:Arabic,Ember:Arabic,Constellation:Arabic,Fireflies:Arabic"}
APP=example/build/macos/Build/Products/Profile/stroke_fx_example.app/Contents/MacOS/stroke_fx_example
# (The app is sandboxed: it writes into its container's temp folder.)
FRAMES="$HOME/Library/Containers/dev.rahiche.strokefx.strokeFxExample/Data/tmp/stroke_fx_frames"
if [ "${RENDER:-1}" != 0 ]; then
  (cd example && flutter build macos --profile --dart-define=CAPTURE="$PAIRS")
  "$APP" 2>&1 | grep -E "CAPTURE"
fi
mkdir -p doc
echo "$PAIRS" | tr ',' '\n' | while IFS=: read -r effect script; do
  name=$(echo "${effect}_${script}" | tr 'A-Z ' 'a-z_')
  dir="$FRAMES/$name"
  [ -d "$dir" ] || { echo "no frames for $name"; continue; }
  ffmpeg -nostdin -loglevel error -y -framerate 30 -i "$dir/f%05d.png" -vf \
    "fps=25,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "doc/$name.gif"
  echo "doc/$name.gif $(du -k "doc/$name.gif" | cut -f1) KB"
done
