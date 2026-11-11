#!/usr/bin/env bash
# Prepares the source of an upstream DBX release with the audit-log patch
# branch applied on top, ready for `docker build`.
#
# Inputs (environment):
#   UPSTREAM_REPO  owner/repo of upstream DBX (t8y2/dbx)
#   FORK_REPO      owner/repo holding PATCH_BRANCH (this fork)
#   PATCH_BRANCH   branch with the audit-log commits (feat/web-audit-log)
#   RELEASE_TAG    stable upstream tag to build (vX.Y.Z)
#   WORKDIR        empty directory to create the source tree in
#
# Outputs (stdout and $GITHUB_OUTPUT when set):
#   tag_commit, patch_commits, already_upstream, source_commit, conflict_files
#
# Exit codes: 0 ok, 2 invalid input / untrusted release, 3 patch conflict.
set -euo pipefail

die() {
  echo "::error::$*" >&2
  exit 2
}

out() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}

: "${UPSTREAM_REPO:?}" "${FORK_REPO:?}" "${PATCH_BRANCH:?}" "${RELEASE_TAG:?}" "${WORKDIR:?}"

# Everything below ends up in git refspecs, URLs and output files: accept
# only the shapes we expect, so nothing can smuggle options or newlines.
repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
[[ $UPSTREAM_REPO =~ $repo_re ]] || die "Invalid UPSTREAM_REPO"
[[ $FORK_REPO =~ $repo_re ]] || die "Invalid FORK_REPO"
[[ $RELEASE_TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Only stable tags (vX.Y.Z) are built, got: $RELEASE_TAG"
[[ $PATCH_BRANCH =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && $PATCH_BRANCH != *..* ]] || die "Invalid PATCH_BRANCH"
[[ ! -e $WORKDIR ]] || die "WORKDIR already exists: $WORKDIR"

# Blobless clone: full commit history (needed to check where the tag comes
# from) without downloading every file version.
git clone --quiet --filter=blob:none --no-checkout --single-branch --branch main \
  "https://github.com/$UPSTREAM_REPO.git" "$WORKDIR"
cd "$WORKDIR"
git fetch --quiet --no-tags origin "+refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"
tag_commit=$(git rev-parse --verify --quiet "refs/tags/$RELEASE_TAG^{commit}") || die "Tag not found: $RELEASE_TAG"

# A release that is not part of upstream main history is not something the
# project published from its main line: refuse to build it.
git merge-base --is-ancestor "$tag_commit" origin/main ||
  die "$RELEASE_TAG ($tag_commit) is not on $UPSTREAM_REPO main"
out tag_commit "$tag_commit"

git -c advice.detachedHead=false checkout --quiet --detach "$tag_commit"

# Once the feature is merged upstream the release already contains it.
if git cat-file -e "$tag_commit:crates/dbx-web/src/audit.rs" 2>/dev/null; then
  out patch_commits 0
  out already_upstream true
  out source_commit "$tag_commit"
  exit 0
fi

git remote add fork "https://github.com/$FORK_REPO.git"
git fetch --quiet --no-tags fork "+refs/heads/$PATCH_BRANCH:refs/remotes/fork/patch"
base=$(git merge-base origin/main fork/patch) || die "$PATCH_BRANCH shares no history with upstream main"

if [[ -n $(git rev-list --merges "$base..fork/patch") ]]; then
  die "$PATCH_BRANCH contains merge commits; keep it linear (rebase instead of merge)"
fi
mapfile -t picks < <(git rev-list --reverse "$base..fork/patch")
((${#picks[@]} > 0)) || die "$PATCH_BRANCH has no commits on top of upstream main"
((${#picks[@]} <= 50)) || die "$PATCH_BRANCH has ${#picks[@]} commits on top of upstream; refusing"
out patch_commits "${#picks[@]}"
out already_upstream false

# Keep git's diagnostics out of the source tree (it is the Docker context).
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
if ! git -c user.name="dbx-audit-build" -c user.email="dbx-audit-build@users.noreply.github.com" \
  cherry-pick -x "${picks[@]}" >"$log_file" 2>&1; then
  cat "$log_file" >&2
  conflicts=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
  git cherry-pick --abort >/dev/null 2>&1 || true
  out conflict_files "${conflicts% }"
  echo "::error::The audit-log patch no longer applies to $RELEASE_TAG: ${conflicts% }" >&2
  exit 3
fi

out source_commit "$(git rev-parse HEAD)"
