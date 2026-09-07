# git-sign-on-push

Sign commits when you push them, not when you make them.

With `commit.gpgsign=true` every commit gets signed as you make it, including the WIP ones you
amend or rebase away five minutes later. This moves the signing to just before a push: one
signature per commit that actually leaves your machine.

## How it works

`sign-unpushed` rebuilds each unpushed commit with `git commit-tree -S`. That keeps author and
committer names, emails and dates exactly as they were, handles merges, works on branches that
aren't checked out, and never touches your index or working tree — so it also works with a dirty
tree, which `git rebase --gpg-sign` does not. The commit SHAs change; that's unavoidable, the
signature lives inside the commit object.

Commits are left alone if they're already signed, or if the committer email isn't yours — your key
never ends up on someone else's commit.

### Why the hook refuses the push

Git works out which commits to send *before* it runs `pre-push`. If the hook rewrote the branch and
let the push continue, git would send the old unsigned commits and your local branch would quietly
end up ahead of the remote. So the hook signs and then fails:

```
pre-push: commits were signed. Run your push again to send them.
```

Push again and the signed commits go out. To avoid the double push, the install sets `git up` and
`git upup` aliases that sign first — then the hook finds nothing to do. The hook stays as the
safety net for everything else: plain `git push`, your IDE, agents.

## Install in one repo

```sh
cd /path/to/repo
/path/to/git-sign-on-push/install.sh
```

That copies `sign-unpushed` and `pre-push` into `.git/hooks/` (untracked, not shared) and sets four
local keys:

| Key | Value |
| --- | --- |
| `commit.gpgsign` | `false` |
| `user.signingkey` | taken from your existing `gpg.signingkey` / `user.signingkey` |
| `alias.up` | sign, then push the current branch |
| `alias.upup` | sign, then force-push the current branch |

`tag.gpgsign` is left alone — tags keep signing at creation time.

It refuses to overwrite an existing, different `pre-push` hook; pass `--force` to overwrite anyway.

### Uninstall

```sh
rm .git/hooks/sign-unpushed .git/hooks/pre-push
git config --local --unset commit.gpgsign
git config --local --unset user.signingkey
git config --local --unset alias.up
git config --local --unset alias.upup
```

## Install for every repo

Instead of running `install.sh` per repo, point git's global `core.hooksPath` at one copy of the
hooks:

```sh
mkdir -p ~/.config/git/hooks
cp sign-unpushed pre-push ~/.config/git/hooks/
chmod +x ~/.config/git/hooks/sign-unpushed ~/.config/git/hooks/pre-push

git config --global core.hooksPath ~/.config/git/hooks
git config --global commit.gpgsign false
git config --global user.signingkey YOUR_KEY_ID
git config --global alias.up   '!f() { ~/.config/git/hooks/sign-unpushed; rc=$?; [ $rc -eq 0 ] || [ $rc -eq 10 ] || exit $rc; git push origin "$(git rev-parse --abbrev-ref HEAD)" "$@"; }; f'
git config --global alias.upup '!f() { ~/.config/git/hooks/sign-unpushed; rc=$?; [ $rc -eq 0 ] || [ $rc -eq 10 ] || exit $rc; git push --force origin "$(git rev-parse --abbrev-ref HEAD)" "$@"; }; f'
```

Three things to know before you do this:

- **`core.hooksPath` disables `.git/hooks` in every repo.** Any repo using husky, lefthook or
  pre-commit stops running its hooks. The `pre-push` here handles that for itself — it hands over
  to `.git/hooks/pre-push` when the repo has one — but other hook types (`pre-commit`,
  `commit-msg`, …) would need the same wrapper treatment, or a symlink from
  `~/.config/git/hooks/<name>` per repo.
- **Use `user.signingkey`, not `gpg.signingkey`.** `gpg.signingkey` isn't a real git setting; if
  your config has it, signing is actually working off the committer-email → key-UID fallback.
  Rename it while you're in there. The real settings are `user.signingKey`, `gpg.program` and
  `gpg.format`.
- **Repos that sign as someone else** need `user.signingkey` (or `commit.gpgsign true`) set
  locally — local config wins over global.

### Uninstall (global)

```sh
git config --global --unset core.hooksPath
git config --global commit.gpgsign true
git config --global --unset user.signingkey
# put your original alias.up / alias.upup back
rm -rf ~/.config/git/hooks
```

## Notes

- `sign-unpushed` can be run on its own; it signs the current branch's unpushed commits and exits
  `10` if it signed anything, `0` if there was nothing to do, `1` on failure. Exit `10` is what the
  `pre-push` hook turns into a refused push, so anything wrapping the script has to treat it as
  success — that's why the aliases above aren't a plain `&&`.
- If you're still prompted for your passphrase constantly after this, gpg-agent isn't caching.
  Check `default-cache-ttl` / `max-cache-ttl` in `~/.gnupg/gpg-agent.conf`.
