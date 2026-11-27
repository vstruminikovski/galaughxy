#!/usr/bin/env bash
# Build the studio as a static site and publish it to the gh-pages branch.
# Usage: scripts/deploy.sh   (run from anywhere; always deploys the current origin/main commit)
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_NAME="$(gh repo view --json name --jq .name)"
OWNER="$(gh repo view --json owner --jq .owner.login)"
BASE="/${REPO_NAME}/"
VITE_BASE="$BASE" npx vite build --base "$BASE"
# keep single-page fallbacks working on Pages
cp dist/index.html dist/404.html
touch dist/.nojekyll
git -C dist init -q -b gh-pages 2>/dev/null || true
cd dist
git add -A
git -c user.name="deploy" -c user.email="deploy@local" commit -qm "Deploy $(git -C .. rev-parse --short HEAD)" || true
git remote remove origin 2>/dev/null || true
git remote add origin "$(git -C .. remote get-url origin)"
git push -q -f origin gh-pages 2>/dev/null
echo "Deployed (once Pages is on): https://${OWNER}.github.io/${REPO_NAME}/"
