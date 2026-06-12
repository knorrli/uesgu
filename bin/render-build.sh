#!/usr/bin/env bash

# Exit on error
set -o errexit

bundle install
bin/rails assets:precompile
bin/rails assets:clean

# Migrations are NOT run here — they run in render.yaml's preDeployCommand (paid
# plan), after a successful build and before the new release goes live.
