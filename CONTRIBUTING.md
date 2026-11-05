# Contributing to YT6801 Auto Installer

Thanks for taking the time to contribute! This document describes how to
report problems, propose changes, and test your work locally.

By participating in this project you agree to abide by the
[Code of Conduct](https://github.com/finallyjay/.github/blob/main/CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** — open an issue using the bug report template and include
  your distribution, kernel version, and the relevant log output from
  `sudo journalctl -u yt6801-reinstall.service`.
- **Suggest an enhancement** — open an issue using the feature request
  template and describe the use case before the implementation.
- **Submit a pull request** — fix a bug, improve documentation, or add
  support for another Debian-based distribution.

## Development setup

This project is a small collection of Bash scripts and a systemd unit.
You do not need a build system, but you will need:

- A Linux machine (or VM) running a Debian-based distribution
- `bash`, `dpkg`, `systemd`
- [`shellcheck`](https://www.shellcheck.net/) for local linting

Clone your fork and create a topic branch:

```bash
git clone https://github.com/<your-fork>/yt6801-auto-installer.git
cd yt6801-auto-installer
git checkout -b my-change
```

## Running checks locally

Before pushing, run the same checks as CI:

```bash
shellcheck $(git ls-files '*.sh')
shfmt -i 4 -d $(git ls-files '*.sh')
bats test/
```

The CI workflow at `.github/workflows/shellcheck.yml` runs these on every
push and pull request targeting `main`. PRs that fail them will not be
merged.

## Testing changes

Because the scripts install a kernel module and manage a systemd service,
please test changes on a disposable VM rather than your daily driver. A
typical test cycle looks like:

1. Run `sudo bash setup.sh` on a fresh VM.
2. Reboot and confirm the `yt6801` module is loaded (`lsmod | grep yt6801`).
3. Simulate a kernel update, reboot, and confirm the service reinstalls
   the driver as expected.
4. Run `sudo bash uninstall.sh` and confirm the service and files are
   removed cleanly.

Attach the relevant log output to your pull request when the change
affects install, reinstall, or reboot behavior.

## Commit messages

- Use the imperative mood ("Fix reboot loop", not "Fixed reboot loop").
- Keep the subject line under 72 characters.
- Explain the motivation for the change in the body when it is not
  obvious from the diff.

## Pull request checklist

Before requesting review, please confirm:

- [ ] ShellCheck, shfmt and `bats test/` pass locally
- [ ] The change is tested on at least one Debian-based distribution
- [ ] README, CHANGELOG, or other docs are updated if behavior changes
- [ ] The PR description explains *why* the change is needed

## Releasing

Releases are built and published by `.github/workflows/release.yml` when a
`vX.Y.Z` tag is pushed:

1. In a PR, set `VERSION` to `X.Y.Z` and turn the `[Unreleased]` section of
   `CHANGELOG.md` into `## [X.Y.Z] - YYYY-MM-DD` (the workflow refuses a tag
   that does not match both).
2. After merging it, tag that commit on `main` and push the tag:
   `git tag vX.Y.Z && git push origin vX.Y.Z`.

The workflow runs the tests, builds the assets with
`tools/build-release.sh` (try it locally with
`tools/build-release.sh X.Y.Z /tmp/dist`), checks their SHA256 sums and
creates the release with the CHANGELOG section as notes.

## License

By contributing, you agree that your contributions will be licensed under
the [GNU General Public License v2.0](LICENSE), the same license as the
rest of the project.
