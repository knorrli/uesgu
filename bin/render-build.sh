#!/usr/bin/env bash

set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

# Render's checkout may not include tag objects, so fetch them before describing.
git fetch --tags --force --quiet 2>/dev/null || true
( git describe --tags --always 2>/dev/null || echo "${RENDER_GIT_COMMIT:0:7}" ) > REVISION
echo "Stamped REVISION = $(cat REVISION)"

# Migrations are NOT run here — see render.yaml's preDeployCommand.
