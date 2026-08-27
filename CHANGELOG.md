# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Code of Conduct (#5)
- CONTRIBUTING guide (#6)
- Security policy (#7)
- Issue templates (#8)
- Pull request template (#9)
- Dependabot configuration for GitHub Actions version updates

### Changed
- Bump `actions/checkout` from 4 to 6 (#10)
- Bump `actions/checkout` from 6 to 7 (#12)

### Fixed
- Fix clone URL placeholder in README (#4)
- Propagate `install_yt6801_if_needed.sh` failures: `dpkg -i` errors now log and exit non-zero instead of being swallowed, and the module is verified with `modprobe` after install (#14)
- Harden the `yt6801-reinstall.service` systemd unit: longer DKMS build timeout, correct network ordering, `ProtectHome`/`PrivateTmp` sandboxing, and explicit journal logging (#15)
- Compare the installed driver version against the `.deb` in `deb/` before skipping install when the module is already loaded, so newer packages are no longer ignored (#17)
- Reset the `yt6801-reinstall.service` failed state during `uninstall.sh` so a stale entry no longer lingers in `systemctl --failed` (#18)
- Require all four scripts to be run as root and drop internal `sudo` calls, so `setup.sh`/`uninstall.sh` can no longer be left in a half-applied state by a cancelled or expired `sudo` prompt partway through
- Run all four scripts under `set -euo pipefail` instead of `set -e`, so an unset variable or a failed command upstream of a pipe is no longer silently ignored

### Security
- Add least-privilege `permissions:` to the ShellCheck workflow, resolving a GitHub code scanning alert (#11)

## [1.0.0] - 2026-03-30

### Added
- Initial release with driver version 1.0.28
- `install_yt6801_if_needed.sh` - Automatic driver installation script
- `check_yt6801_and_reboot.sh` - Module verification and reboot script
- `yt6801-reinstall.service` - systemd service for boot-time driver check
- `setup.sh` - Automated installation script
- `uninstall.sh` - Automated uninstallation script
- Auto-detection of `.deb` package in `deb/` directory
- GitHub Actions CI with ShellCheck linting
- GPL-2.0 license
