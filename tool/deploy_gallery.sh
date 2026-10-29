#!/bin/sh
# Builds the example for the web and puts it on the gh-pages branch:
#   https://rahiche.github.io/stroke_fx/            WebAssembly (skwasm), or
#                                                   JavaScript where a browser
#                                                   can't run WasmGC
#   https://rahiche.github.io/stroke_fx/canvaskit/  JavaScript (CanvasKit)
# Run from the package's root:
#   sh tool/deploy_gallery.sh
set -e
DIR=$(mktemp -d)
(cd example && flutter build web --release --wasm --base-href /stroke_fx/)
cp -R example/build/web/. "$DIR"
(cd example && flutter build web --release --base-href /stroke_fx/canvaskit/)
mkdir -p "$DIR/canvaskit"
cp -R example/build/web/. "$DIR/canvaskit"
touch "$DIR/.nojekyll"
cd "$DIR"
git init -q -b gh-pages
git add -A
git commit -q -m "The gallery, built from main: WebAssembly at the root, CanvasKit in canvaskit/"
git push -q -f https://github.com/Rahiche/stroke_fx.git gh-pages
echo "Pushed to gh-pages: https://rahiche.github.io/stroke_fx/ (and canvaskit/)"
