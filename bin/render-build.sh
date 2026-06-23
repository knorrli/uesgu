#!/usr/bin/env bash

# Exit on error
set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

# Stamp the deployed version for the footer. We only ever deploy release tags
# (render.yaml autoDeployTrigger is off; deploys are triggered by the release
# workflow with ?ref=<tag>), so `git describe --tags` resolves to a clean tag
# like "v0.1.0". Fall back to the short commit SHA if the tag isn't reachable.
( git describe --tags --always 2>/dev/null || echo "${RENDER_GIT_COMMIT:0:7}" ) > REVISION
echo "Stamped REVISION = $(cat REVISION)"

# Migrations are NOT run here — they run in render.yaml's preDeployCommand (paid
# plan), after a successful build and before the new release goes live.
