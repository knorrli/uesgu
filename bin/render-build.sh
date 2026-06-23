#!/usr/bin/env bash

# Exit on error
set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

# Stamp the deployed version for the footer. The `release` branch always points
# at a release tag's commit (the release workflow fast-forwards it), so
# `git describe --tags` resolves to a clean tag like "v0.1.0". Render's checkout
# may not include tag objects, so fetch them first; fall back to the short commit
# SHA if no tag is reachable.
git fetch --tags --force --quiet 2>/dev/null || true
( git describe --tags --always 2>/dev/null || echo "${RENDER_GIT_COMMIT:0:7}" ) > REVISION
echo "Stamped REVISION = $(cat REVISION)"

# Migrations are NOT run here — they run in render.yaml's preDeployCommand (paid
# plan), after a successful build and before the new release goes live.
