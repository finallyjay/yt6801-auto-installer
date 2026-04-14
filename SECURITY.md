# Security Policy

Thank you for helping keep YT6801 Auto Installer and its users safe.

## Supported versions

This project tracks a single active line. Only the latest release on the
`main` branch receives fixes. If you are running an older version, please
upgrade before reporting an issue.

| Version | Supported |
|---------|-----------|
| Latest `main` | Yes |
| Older tags    | No  |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Instead, report the issue privately using GitHub's
[private vulnerability reporting][advisory] feature on this repository:

1. Go to the [Security tab][security-tab] of this repository.
2. Click **Report a vulnerability**.
3. Fill out the form with a clear description, reproduction steps, and the
   impact you observed.

If you are unable to use private vulnerability reporting, you may contact
the maintainer [@finallyjay](https://github.com/finallyjay) directly on
GitHub and request a private channel.

## What to include

A good report contains:

- The affected file, script, or systemd unit
- The distribution and kernel version you reproduced on
- Exact steps to reproduce
- The observed impact (e.g., privilege escalation, persistence, data
  exposure)
- Any logs from `/opt/yt6801-auto-installer/install_yt6801.log` or
  `journalctl -u yt6801-reinstall.service` that help confirm the issue

## What to expect

- **Acknowledgement:** within 7 days of receiving your report.
- **Triage:** the maintainer will investigate, confirm the impact, and
  agree on a fix timeline with you.
- **Fix and disclosure:** once a fix is available, a release will be
  published and the advisory will be made public, crediting the reporter
  unless they prefer to remain anonymous.

## Scope

In scope:

- The shell scripts in this repository (`setup.sh`, `uninstall.sh`,
  `install_yt6801_if_needed.sh`, `check_yt6801_and_reboot.sh`)
- The systemd unit (`yt6801-reinstall.service`)
- The packaging of the `.deb` driver file shipped under `deb/`

Out of scope:

- Vulnerabilities in the upstream Motorcomm/Tuxedo YT6801 driver itself —
  please report those to the driver vendor.
- Issues that require an attacker to already have root on the target
  machine.

Thank you for practicing responsible disclosure.

[advisory]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability
[security-tab]: https://github.com/finallyjay/yt6801-auto-installer/security
