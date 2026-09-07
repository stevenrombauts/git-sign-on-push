#!/bin/sh
#
# install.sh - install the sign-on-push hooks into the git repo you run it from.
#
#   ./install.sh           install, refusing to overwrite a different pre-push hook
#   ./install.sh --force   overwrite it anyway
#
# Everything it writes is local to the repo: two files in .git/hooks and four
# keys in .git/config. See README.md for the global (all repos) setup.

set -eu

force=0
if [ "${1:-}" = "--force" ]; then
	force=1
fi

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "install: not inside a git repository" >&2
	exit 1
fi

HOOKS="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOKS"

if [ -e "$HOOKS/pre-push" ] && [ "$force" -eq 0 ]; then
	if ! cmp -s "$SRC/pre-push" "$HOOKS/pre-push"; then
		echo "install: $HOOKS/pre-push already exists and differs." >&2
		echo "install: re-run with --force to overwrite it." >&2
		exit 1
	fi
fi

cp "$SRC/sign-unpushed" "$SRC/pre-push" "$HOOKS/"
chmod +x "$HOOKS/sign-unpushed" "$HOOKS/pre-push"

# gpg.signingkey is not a real git setting, but it is what the config may have.
key=$(git config --get gpg.signingkey || git config --get user.signingkey || true)

git config --local commit.gpgsign false
if [ -n "$key" ]; then
	git config --local user.signingkey "$key"
else
	echo "install: no signing key found; git will fall back to your committer email" >&2
fi

# tag.gpgsign is left alone - tags keep signing at creation time.
git config --local alias.up '!.git/hooks/sign-unpushed && git push origin $(git rev-parse --abbrev-ref HEAD)'
git config --local alias.upup '!.git/hooks/sign-unpushed && git push origin --force $(git rev-parse --abbrev-ref HEAD)'

echo "install: hooks in $HOOKS, local config set."
echo "install: commits are no longer signed at commit time; 'git up' or 'git push' signs them."
