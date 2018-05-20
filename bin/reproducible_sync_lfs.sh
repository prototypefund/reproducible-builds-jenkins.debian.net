#!/bin/sh

set -eux

base=/srv/reproducible-builds.org

cd "$base"
if [ ! -d lfs ]; then
    # GIT_URL comes from Jenkins
    git clone "$GIT_URL" lfs
    cd lfs
    git lfs install
fi
cd lfs
git pull
git lfs pull
