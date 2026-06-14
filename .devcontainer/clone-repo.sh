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
  if [ ! -d "${target}/.git" ]; then
    gh repo clone "${effective}" "${target}"
  fi
  # Ensure an 'upstream' remote points at the canonical repo when a fork is in
  # use. Done on every run (and idempotently) so it self-heals if a previous
  # attempt failed or the repo predates the fork override.
  if [ "${effective}" != "${canonical}" ] &&
    ! git -C "${target}" remote get-url upstream >/dev/null 2>&1; then
    git -C "${target}" remote add upstream "https://github.com/${canonical}.git"
  fi
}

clone_repo "$@"
