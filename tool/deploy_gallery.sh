#!/bin/sh
# Builds the example for the web and puts it on the gh-pages branch, served at
# https://rahiche.github.io/stroke_fx/. Run from the package's root:
#   sh tool/deploy_gallery.sh
set -e
(cd example && flutter build web --release --base-href /stroke_fx/)
DIR=$(mktemp -d)
cp -R example/build/web/. "$DIR"
touch "$DIR/.nojekyll"
cd "$DIR"
git init -q -b gh-pages
git add -A
git commit -q -m "The gallery, built from main"
git push -q -f https://github.com/Rahiche/stroke_fx.git gh-pages
echo "Pushed to gh-pages: https://rahiche.github.io/stroke_fx/"
