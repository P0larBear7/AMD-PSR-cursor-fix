# AMD PSR Cursor Fix

A reversible Windows workaround for mouse-pointer stutter caused by an AMD driver's panel-self-refresh cursor path.

In the investigated case, disabling PSR reduced the median pointer callback from about **0.496 ms to 0.038 ms**. The owner confirmed smooth movement with the original cursor and a 1000 Hz mouse. The test used a Radeon RX 7700S driving a laptop's internal panel. Other systems need individual validation.

## Quick start

1. Download and extract the ZIP from [Releases](https://github.com/P0larBear7/amd-psr-cursor-fix/releases).
2. Double-click **Start.cmd**.
3. Choose **Apply cursor fix**, then select the AMD GPU shown under **Connected to** in Windows **Settings → System → Display → Advanced display**.
4. Allow the administrator prompt. Choose a display-device restart to activate the setting immediately, or restart Windows later. The screen may blink during a device restart.
5. Test the original cursor at the mouse's usual polling rate on the desktop, text fields and links.

Disabling PSR may increase idle display power consumption. Use **Restore saved setting** to undo the change. **Use driver default** removes the override explicitly, which is useful when a driver reinstall has created a new adapter registry key and its old backup no longer applies.

The tools use Windows PowerShell 5.1 and Windows' built-in PnP utilities. Python and third-party modules are unnecessary. The launchers set execution policy only for their PowerShell process. Managed Windows policy can still restrict execution.

## When this may help

The symptoms worth comparing are a high-polling-rate external mouse stuttering on the desktop, improvement at a lower polling rate, and a strong relationship to which GPU drives the internal panel. A smooth touchpad, older driver, or software-composed cursor provides additional evidence.

The workaround sets `DalPSRFeatureEnable` to `0` as a DWORD in the **selected adapter's** registry key. This is a private AMD driver setting whose consumer was inspected in the tested Windows driver. Its availability and effect can vary across AMD versions and hardware.

The confirmed software target is Windows 11 with AMD Adrenalin **26.11.1**, RX driver **32.0.32015.16001**. The observed regression began between **25.9.2** and **25.10.2** on the reference system. Windows 10 2004+ supplies the device-restart command, but this project has not validated the workaround on Windows 10. Use 64-bit Windows PowerShell on a supported AMD Windows installation.

## What is included

| File | Purpose |
|---|---|
| `Start.cmd` | Interactive Apply, Restore, Default and Status menu |
| `Fix-Cursor.ps1` | The same operations from the command line |
| `ASUS-Extension.cmd` | Optional installation of a matching original ASUS extension |
| `Install-ASUS-Extension.ps1` | Check or install that ASUS package |
| [Technical report](docs/TECHNICAL-REPORT.md) | Mechanism, evidence, limitations and reproduction procedure |
| [ASUS compatibility notes](docs/ASUS-COMPATIBILITY.md) | OEM policies, applicability and installation details |
| [Measurements](docs/measurements.json) | Sanitized results from the reference investigation |

## Command-line use

Run these from the extracted project folder. Status is read-only. Changes request administrator access if needed.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-Cursor.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-Cursor.ps1 -Action Apply -Restart
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-Cursor.ps1 -Action Restore -Restart
```

On a computer with multiple AMD GPUs, the tool asks which one to change. For unattended selection, supply the exact `-AdapterId` shown by Status. Omit `-Restart` to activate the change on a later Windows restart.

Backups are stored under `HKLM\SOFTWARE\AMDPSRCursorFix\Backups`, indexed by the device instance and adapter registry path. Repeated Apply preserves the original backup. Restore restores the previous type and value, including original absence. If PSR was already disabled before the tool's first Apply, Restore correctly preserves that pre-existing state.

Status reports the registry policy. It cannot read the firmware's live PSR state. Confirm the effect through mouse behavior after activation. Check Status again after driver updates, GPU mode changes or a clean reinstall.

## ASUS support

The optional helper uses the original signed `amduw23e.inf` package from an ASUS driver download for the laptop model. It checks hardware-ID matches and catalog signatures, then asks Windows to install the extension and its declared PCI bridge dependency. Obtain the files from ASUS and follow the [ASUS instructions](docs/ASUS-COMPATIBILITY.md).

The extension was already active when the reference system stuttered. Its display-specific policies are relevant to OEM compatibility, while the PSR override supplies the demonstrated cursor improvement. Additional stability or battery benefits from the extension have not been measured.

## Validation and contributions

The project includes registry lifecycle tests that run in an isolated current-user test key. Run them with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PsrFix.ps1`. GitHub Actions runs the same tests on Windows.

Please report the GPU driving the panel, laptop and panel model, driver version, Windows build, mouse polling rate and before/after result. The issue templates include these fields. The most valuable follow-up tests are reboot persistence, sleep/wake, battery impact and additional hardware. [Contribution guide](CONTRIBUTING.md)

Licensed under MIT for this project's original code and documentation. AMD and ASUS driver packages retain their own licenses and are obtained separately. This is an independent community project.
