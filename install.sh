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

# core.hooksPath replaces .git/hooks, it does not add to it. If this repo has one
# set, anything copied into .git/hooks is dead weight, so stop instead.
hookspath=$(git config --get core.hooksPath || true)
if [ -n "$hookspath" ]; then
	echo "install: this repo reads its hooks from $hookspath (core.hooksPath)." >&2
	if [ "$force" -eq 0 ]; then
		echo "install: git ignores .git/hooks here, so installing there would do nothing." >&2
		echo "install: copy sign-unpushed and pre-push into that directory instead," >&2
		echo "install: unset core.hooksPath, or run this again with --force." >&2
		exit 1
	fi
	echo "install: --force given, writing to .git/hooks anyway. Git will not run these" >&2
	echo "install: hooks until core.hooksPath is unset or points at them." >&2
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
# sign-unpushed exits 10 when it signed something, which is a success here, so
# these can't just use "&&".
git config --local alias.up '!f() { .git/hooks/sign-unpushed; rc=$?; [ $rc -eq 0 ] || [ $rc -eq 10 ] || exit $rc; git push origin "$(git rev-parse --abbrev-ref HEAD)" "$@"; }; f'
git config --local alias.upup '!f() { .git/hooks/sign-unpushed; rc=$?; [ $rc -eq 0 ] || [ $rc -eq 10 ] || exit $rc; git push --force origin "$(git rev-parse --abbrev-ref HEAD)" "$@"; }; f'

echo "install: hooks in $HOOKS, local config set."
echo "install: commits are no longer signed at commit time; 'git up' or 'git push' signs them."
