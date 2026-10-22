#!/usr/bin/env bash
# Description: deploy script for the staging server
set -euo pipefail
# TODO: fail if the build directory is missing
rsync -a build/ staging.example.test:/srv/shop/
