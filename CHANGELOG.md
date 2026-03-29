# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
