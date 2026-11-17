# Contributing

Useful reports identify whether the same PSR-dependent symptom occurs on another driver, panel or GPU. Include the GPU shown under Connected to, the driver version for that GPU, Windows build, display refresh rate, mouse model/connection/polling rate, and behavior before Apply, after Apply and after Restore.

Please test with an ordinary cursor. Pointer trails or a padded-cursor workaround can hide the hardware-cursor path under investigation. If possible, include observations after reboot and sleep/wake and whether power source changes the result.

Run `tests/Test-PsrFix.ps1` in Windows PowerShell 5.1 before submitting changes to the registry logic. It uses an isolated HKCU subtree and exercises absent values, typed restoration, repeated operations, interrupted-operation recovery and separate adapters. Code changes should preserve the original backup before any adapter write and keep changes scoped to the selected device.

The source is plain PowerShell, batch launchers and Markdown. The public release uses a small ZIP with SHA-256 checksums. This keeps behavior inspectable and avoids a separate executable build chain.

Review diagnostic material before uploading. Raw ETL and system dumps can contain local paths and process information. Prefer a concise result or sanitized measurements unless a maintainer requests a trace and you have reviewed its contents.

Promising follow-up work includes broader hardware validation, idle-power measurements and testing future driver releases with the override removed. OEM policy changes should come with the original package identity, matching hardware evidence and a measured reason for the change.
