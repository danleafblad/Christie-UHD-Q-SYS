# Christie UHD Q-SYS Plugin

A Q-SYS plugin for Christie Access series LCD panels (UHD551-L, UHD651-L, UHD751-P, UHD861-P) controlled over TCP port 1986.

It confirms every change instead of just sending it. Each command is followed by a query, and the plugin keeps retrying until the panel reports the requested state. If the panel never confirms, the Status control raises a fault.

## Features

- **Confirmed power.** Uses `SETQUICKSTANDBY` with a `GETQUICKSTANDBY` check and retries up to a set number of attempts.
- **Audio policy:** user control, force mute, force volume to minimum, or both.
- **Input policy:** user selectable from a drop-down list, or forced to one input.
- **Power-on defaults** (Defaults page): set the input and/or volume and mute once each time the display turns on. Unlike forced settings, users can change them afterwards.
- **Forced settings come back.** They're applied again every time the panel wakes, and whenever polling shows someone changed them (for example with the IR remote).
- **Mute is toggle-safe.** `SETMUTE` toggles on these panels, so it's only sent when the plugin knows the current state is wrong. It's never sent again until a fresh reply shows the new state.
- **Every command string can be edited** in Properties, so you can match other firmware or models without touching code.
- **Setup page** with a raw command box and the last reply, for testing on site.

One plugin instance controls one display.

## Install

1. Copy `ChristieDisplayControl.qplug` to `Documents\QSC\Q-Sys Designer\Plugins`.
2. Restart Q-SYS Designer. The plugin appears under **Plugins > Christie > Display Control (Confirmed Power)**.
3. Drag one into the design for each display and set its **IP Address** on the Setup page.

## Panel setup

- Enable **Quick Standby** on each panel: OSD **System > Settings > More > Quick Standby**. Without it, `SETQUICKSTANDBY` does nothing.
- Give each panel a static IP address or a DHCP reservation.

## Controls

| Control | Page | Pin | Notes |
|---|---|---|---|
| Power On / Power Off | Control | Input | Trigger buttons |
| Power State | Control | Output | LED, lit when the panel reports it's on |
| Status | Both | Output | OK / compromised / fault / initializing, with text |
| Volume | Control | Both | Fader with Volume Min to Volume Max. Disabled when forced |
| Mute | Control | Both | Toggle. Disabled when forced |
| Input | Control | Both | Drop-down list. Disabled when forced |
| Apply Input On Power-On | Defaults | Both | Toggle. Disabled when the input is forced |
| Power-On Input | Defaults | Both | Drop-down list of the Input List names |
| Apply Audio On Power-On | Defaults | Both | Toggle. Applies Power-On Volume and Power-On Mute |
| Power-On Volume | Defaults | Both | Fader. Disabled when volume is forced |
| Power-On Mute | Defaults | Both | Toggle. Disabled when mute is forced |
| IP Address | Setup | Input | Changing it reconnects |
| Connected | Setup | Output | LED |
| Send Raw / Last Reply | Setup | none | For testing. The login command is sent before the raw command |

## Power-on defaults vs forced settings

| | Forced (Properties) | Power-on defaults (Defaults page) |
|---|---|---|
| When applied | Always: at wake, and again whenever it drifts | Once per power-on |
| Can users change it? | No. Controls are disabled and changes are reverted | Yes, until the next power-on |
| Set where | Designer properties (needs a redeploy) | Runtime controls, which can be pinned or put on a UCI |

Power-on defaults apply when:
- the display goes from standby to on, whether the plugin turned it on or someone used the IR remote (the remote case is detected on the next poll);
- **Power On** is pressed, even if the display is already on. This makes Power On also work as "reset to defaults".

They aren't applied when the plugin starts (for example after a Core reboot) and finds the display already on.

If a setting is forced, the forced value wins and the matching default control is disabled.

## Properties

| Property | Default | Notes |
|---|---|---|
| Port | 1986 | |
| Password | 0000 | Substituted into the login command |
| Poll Interval (s) | 20 | How often state is checked when nothing is pending |
| Retry Interval (s) | 6 | Time between attempts while a change is unconfirmed |
| Max Attempts | 10 | After this many, Status shows a fault. User requests are dropped. Forced settings keep retrying once per poll interval |
| Inter-Command Delay (ms) | 200 | Gap between lines sent to the panel |
| Confirm Delay (s) | 2 | Wait after a set command before querying |
| Audio Mode | User Control | User Control / Force Mute / Force Volume Min / Force Mute + Volume Min |
| Volume Min / Volume Max | 0 / 100 | Fader range. "Force Volume Min" uses Volume Min |
| Input Mode | User Selectable | User Selectable / Forced |
| Input List | `HDMI1=7,HDMI2=8,DP=19,DVI=18,VGA=12,OPS=20` | `Label=Code` pairs. The label is shown in the drop-down list and matched against `GETSOURCE` replies. The code is sent with `SELECTSOURCE` |
| Forced Input | HDMI1 | Shown when Input Mode is Forced |
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
- **forced:**
  - Mute, minimum volume and the forced input are applied, even when a mute reply is lost, with exactly one toggle.
  - They're re-applied after someone changes them with the remote, and after standby and wake.
  - User changes are ignored while forced.
- **user:** input, volume and mute changes work, including mute retries when the panel ignores the toggle.
- **defaults:** defaults are applied on power-on. User changes afterwards are kept across polls. Defaults are applied again after standby and a wake from the remote.
- **defaults_boot:** defaults aren't applied when the panel is found already on at startup, but pressing Power On applies them.
- **defaults_with_forced_mute:** volume and input defaults apply, and forced mute overrides the mute default.

Run from the repo root with Lua 5.3 or newer:

```bash
lua tests/run_tests.lua
```

The tests check the plugin's logic, not real hardware. Confirm the reply formats on your panels with the Setup page's Send Raw box.
