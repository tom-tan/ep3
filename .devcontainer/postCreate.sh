#!/bin/sh

sudo ./.devcontainer/install-medal.sh || exit 1
sudo ./.devcontainer/install-medal-hook.sh || exit 1
./.devcontainer/setup-es.sh || exit 1

test -d cwl || git clone --depth 1 https://github.com/common-workflow-language/common-workflow-language.git /workspace/ep3/cwl
