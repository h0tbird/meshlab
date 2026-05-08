#!/usr/bin/env bash
#
# Clone a repo into the devcontainer workspace if not already present.
# When the effective repo differs from the canonical one (i.e. a fork is in
# use), an 'upstream' remote pointing at the canonical repo is added.
#
# Usage: clone-repo.sh <canonical-owner/repo> <effective-owner/repo> <target-dir>

set -euo pipefail

clone_repo() {
  local canonical="$1" effective="$2" target="$3"
  [ -d "${target}/.git" ] && return 0
  gh repo clone "${effective}" "${target}"
  if [ "${effective}" != "${canonical}" ]; then
    git -C "${target}" remote add upstream "https://github.com/${canonical}.git"
  fi
}

clone_repo "$@"
