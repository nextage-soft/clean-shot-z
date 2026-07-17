# Security Policy

## Supported versions

Only the latest release (and `master`) receive security fixes.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** on this repository
(Security tab → Report a vulnerability) instead of opening a public issue.

You should get a first response within a few days. Please include steps to
reproduce and, if relevant, which area is affected (capture pipeline, editor,
file/project codec, OCR, or the build/signing path).

CleanShot Z is intentionally privacy-preserving — no network calls, no
telemetry, no account. The most security-relevant surfaces are the
Screen-Recording-permissioned capture path and the `.cleanshotz` project
parser (reads untrusted files); reports there are especially appreciated.
