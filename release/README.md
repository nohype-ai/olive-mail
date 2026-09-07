# olive-mail Homebrew Release

Expects [homebrew-tap](https://github.com/nohype-ai/homebrew-tap) as a sibling of this repo. The GitHub repo must be public so the tag tarball is fetchable.

**Run `release.sh` on a Mac.** It bottles that Mac (ready-to-go `brew install`). Linux brew installs compile from source. The bottle is committed to `homebrew-tap/Bottles/` and pushed with the formula — same git remotes you already use.

## Release via Script

Release a new patch version:
```zsh
./release.sh patch
```

Release a new minor version:
```zsh
./release.sh minor
```

Release a new major version:
```zsh
./release.sh major
```

No tags yet → first release is `v0.1.0` (any of the three bumps). Re-run the same command if a release stops mid-bottle: it resumes that version instead of bumping.

## Release Manually

1. Tag the release in the olive-mail repo and push:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. Compute the sha256 of the source tarball GitHub just created:
   ```bash
   curl -sL https://github.com/nohype-ai/olive-mail/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```

3. Generate `homebrew-tap/Formula/olive-mail.rb` from `olive-mail_template.rb`: put the version in the URL and the hash in `sha256`.

4. On a Mac, bottle and put the tarball in the tap:
   ```bash
   brew tap nohype-ai/tap
   cp ../homebrew-tap/Formula/olive-mail.rb "$(brew --repository nohype-ai/tap)/Formula/olive-mail.rb"
   brew reinstall --build-from-source nohype-ai/tap/olive-mail
   brew bottle --no-rebuild --json \
     --root-url=https://raw.githubusercontent.com/nohype-ai/homebrew-tap/main/Bottles \
     nohype-ai/tap/olive-mail
   ```
   Copy the bottle tarball into `homebrew-tap/Bottles/` under the filename Homebrew will request, and merge the bottle block into `olive-mail.rb`. Linux stays unbottled (source build).

5. Commit and push the formula **and** `Bottles/` to the `homebrew-tap` repo. Users who already have the tap will get the update on their next `brew upgrade`.

6. Test olive-mail release
   ```zsh
   brew tap nohype-ai/tap

   # Initial install (Mac: bottle. Linux: compiles.)
   brew install nohype-ai/tap/olive-mail

   # force tap update after new release
   cd $(brew --repository nohype-ai/tap) && git pull

   # Upgrade
   brew upgrade olive-mail

   # Check version
   brew list --versions olive-mail
   ```
