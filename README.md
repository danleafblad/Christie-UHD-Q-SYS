# Christie UHD Q-SYS Plugin

A Q-SYS plugin for Christie Access series LCD panels (UHD551-L, UHD651-L, UHD751-P, UHD861-P) controlled over TCP port 1986.

It confirms every change instead of just sending it. Each command is followed by a query, and the plugin keeps retrying until the panel reports the requested state. If the panel never confirms, the Status control raises a fault.

## Features

- **Confirmed power.** Uses `SETQUICKSTANDBY` with a `GETQUICKSTANDBY` check and retries up to a set number of attempts.
- **Volume, Mute and Input on one page, each with a Force toggle.** Without Force, the control works normally and shows what the display reports. With Force on, the control's value is held: it's applied whenever the display turns on and put back if someone changes it at the display or with the IR remote.
- **Mute is toggle-safe.** `SETMUTE` toggles on these panels, so it's only sent when the plugin knows the current state is wrong. It's never sent again until a fresh reply shows the new state.
- **Every command string can be edited** in Properties, so you can match other firmware or models without touching code.
- **Setup page** with a raw command box and the last reply, for testing on site.

One plugin instance controls one display.

## Install

1. Copy `ChristieDisplayControl.qplug` to `Documents\QSC\Q-Sys Designer\Plugins`.
2. Restart Q-SYS Designer. The plugin appears under **Plugins > Christie > Display Control (Confirmed Power)**.
3. Drag one into the design for each display and set its **IP Address** on the Setup page. If you've changed the panel PIN from `0000`, set **Password** too.

## Panel setup

- Enable **Quick Standby** on each panel: OSD **System > Settings > More > Quick Standby**. Without it, `SETQUICKSTANDBY` does nothing.
- Give each panel a static IP address or a DHCP reservation.

## Controls

| Control | Page | Pin | Notes |
|---|---|---|---|
| Power On / Power Off | Control | Input | Trigger buttons |
| Power State | Control | Output | LED, lit when the panel reports it's on |
| Status | Both | Output | OK / compromised / fault / initializing, with text |
| Volume | Control | Both | Fader, Volume Min to Volume Max |
| Mute | Control | Both | Toggle |
| Input | Control | Both | Drop-down list of the Input List names |
| Force Volume / Force Mute / Force Input | Control | Both | Toggles. Hold the value of the control above them (see below) |
| IP Address | Setup | Input | Changing it reconnects |
| Password | Setup | Input (pin off by default) | Panel PIN, substituted into the login command. Defaults to `0000` when blank. Changing it logs in again immediately |
| Connected | Setup | Output | LED |
| Send Raw / Last Reply | Setup | none | For testing. The login command is sent before the raw command |

## Force toggles

| | Force off | Force on |
|---|---|---|
| Control shows | What the display reports, including remote changes | The value being held |
| Changing the control | Sends it once and confirms | Sends it, confirms, and makes it the new held value |
| Display turns on | Nothing is changed | Held value is applied |
| Someone changes it at the display or remote | Kept, and the control updates to match | Put back on the next poll (within the Poll Interval) |

Examples:
- **Always come on muted at volume 0:** set Mute on and Volume to 0, then turn on Force Mute and Force Volume.
- **Lock the lobby TVs to HDMI1:** pick HDMI1, then turn on Force Input.

Held values are also applied when the plugin starts, for example after a Core reboot, if the display is already on. Status marks held settings, for example `On - HDMI1 (forced), muted (forced), vol 0 (forced)`.

The Force toggles and the controls' values are ordinary control values, so set them in Designer before you save and deploy to make them part of the design.

## Properties

| Property | Default | Notes |
|---|---|---|
| Port | 1986 | |
| Poll Interval (s) | 20 | How often state is checked when nothing is pending |
| Retry Interval (s) | 6 | Time between attempts while a change is unconfirmed |
| Max Attempts | 10 | After this many, Status shows a fault. Unforced requests are dropped. Forced settings keep retrying once per poll interval |
| Inter-Command Delay (ms) | 200 | Gap between lines sent to the panel |
| Confirm Delay (s) | 2 | Wait after a set command before querying |
| Volume Min / Volume Max | 0 / 100 | Volume fader range |
| Input List | `HDMI1=7,HDMI2=8,DP=19,DVI=18,VGA=12,OPS=20` | `Label=Code` pairs. The label is shown in the drop-down list and matched against `GETSOURCE` replies. The code is sent with `SELECTSOURCE` |
| Show Command Strings | false | Reveals the command properties below |
| Debug Output | false | Prints TX/RX lines in the debug window |

### Command strings (defaults)

| Function | Query | Set | Reply example |
|---|---|---|---|
| Login | | `SETUSERSECLEVEL ADMIN {pw}` | |
| Power | `GETQUICKSTANDBY` | `SETQUICKSTANDBY off` (on) / `SETQUICKSTANDBY on` (standby) | `#*Quick Standby is off.` |
| Volume | `GETVOLUME` | `STV {v}` | `#*volume level is 7` |
| Mute | `GETMUTE` | `SETMUTE` (toggle) | `#*MUTE ON` |
| Input | `GETSOURCE` | `SELECTSOURCE {v}` | `#*source is VGA` |

These come from Christie's *Access Series LCD Panels External Commands* reference, 020-102554-06. `SETUSERSECLEVEL` isn't in that 2018 document, but newer panel firmware ignores commands until it has been sent. Clear the login command if your panels don't need it.

### Input codes

`SELECTSOURCE` codes from the reference: 5 = Back AV, 7 = HDMI1, 8 = HDMI2, 11 = YPbPr, 12 = VGA, 18 = DVI, 19 = DP, 20 = OPS. HDMI3 isn't listed. If your panel has it, find its code with the Send Raw box and add it to Input List.

If `GETSOURCE` names an input differently from your label, the plugin can't match it, and Status shows the reported name. Change the label to match. Spaces, case, `_` and `-` are ignored, and "DisplayPort" is treated as "DP".

## Tests

`tests/` has a simulated Christie panel that answers in the reply formats above. It toggles mute like the real panel, resets audio on wake, and can be made to ignore commands or drop replies. It runs the plugin through these scenarios:

- **power_retry:** the panel ignores the first two power commands, and the plugin confirms on the third attempt.
- **power_fail:** the panel never responds. The plugin sends exactly Max Attempts commands, then shows a fault.
- **forced:** with all three forced (muted, volume 0, HDMI1):
  - They're applied on power-on, even when a mute reply is lost, with exactly one toggle.
  - A remote change is put back on the next poll.
  - Moving a forced control changes the held value, and the new value is then held (including a forced unmute).
  - Held values are re-applied after standby and wake.
- **forced_boot:** held values are applied at startup when the display is already on.
- **force_toggle:** without Force, the controls follow the display and remote changes are kept. Turning Force Input on holds the current input. Turning it off lets remote changes stand again.
- **user:** input, volume and mute changes work, including mute retries when the panel ignores the toggle.
- **pin:** a wrong PIN is flagged on Status ("check PIN"). Correcting it in the text box recovers immediately, without reconnecting.

Run from the repo root with Lua 5.3 or newer:

```bash
lua tests/run_tests.lua
```

The tests check the plugin's logic, not real hardware. Confirm the reply formats on your panels with the Setup page's Send Raw box.
