Attendance Addon (att)

Author: Nils, literallywho
Version: 3.0

A lightweight Ashita v4 addon for taking attendance in Final Fantasy XI.
Provides both a command-based workflow (/att) and a full GUI launcher (/attend).
Supports LS1/LS2, self-attendance, zone scanning, delay control, and CSV export.

Installation

Place the entire "att" folder into your Ashita addons directory.

Inside the folder you should have:

att.lua

resources/jobs.csv

resources/zones.csv

resources/shortnames.txt

resources/creditnames.txt

resources/satimers.txt (optional)

Load the addon in game:
/addon load att

Files and Logs

att.lua
Main addon script.

resources/jobs.csv
Maps job IDs to job abbreviations.

resources/zones.csv
Maps zone IDs to zone names.

resources/shortnames.txt
Contains alias,Full Event Name pairs.

resources/creditnames.txt
Supports categories using lines like:
-- HNMS
-- Events
Event lines use: Full Event Name,Zone Name[,Search Area].

resources/satimers.txt
Controls self-attendance duration and reminder intervals.

Log Folders:
HNM Logs/
Event Logs/

Core Commands

/att
Runs attendance. Defaults to alliance-based, HNM mode, event = Current Zone.

/att ls
Zone-based attendance using LS1. Recommended for large groups.

/att ls2
Zone-based attendance using LS2.

/att {alias}
Uses the alias from shortnames.txt to determine the event.

/att sa
Self-attendance mode (requires ls or ls2).

/att h
Immediate write as HNM (skips GUI).

/att e
Immediate write as Event (skips GUI).

/att here
Auto-detect event based on your current zone and run attendance.

/att help
Opens in-game help window.

/attend
Opens or closes the GUI event launcher.

/attend open | close | toggle
Explicit control of the launcher.

Important Usage Notes

• If you use /att without ls or ls2, attendance is based ONLY on your alliance.
This is limited to a maximum of 18 players.

• If you use /attend without LS mode active, it may not capture more than ~45 players.
The launcher is intended to work with the linkshell player list, not the alliance list.

• For large events ALWAYS use ls or ls2, either manually or through the "Use LS2" checkbox in /attend.

The Att Launcher (/attend)

Top Settings Row:

Use LS2 checkbox
All operations use LS2 (sea, LS messages, attendance mode).

Self Attest checkbox
Event buttons run self-attendance mode.

Delay setting
Controls the delay between /sea and /att (0–99 seconds).

Update Zone button
Refreshes the Suggested Events list for your current zone.

Suggested Events:
At the top of the window, shows events matching your current zone.

Event Categories:
Derived from creditnames.txt.
Each category is a collapsible header containing event buttons.
Each event button has its matching "/sea <area> linkshell" hint to the right.

Clicking an event button:
Runs /sea for that event.
After the configured delay, runs /att ls or /att ls2.
If Self Attest is enabled, runs with /att ls sa or /att ls2 sa.

Attendance Results Window

Opened after any successful /att run.

Displays:

Mode (HNM or Event)

Event name

Credit zones

Attendee list with Remove buttons

Buttons:

Write
Writes CSV and sends LS message.

Write & Close
Writes CSV, sends LS message, closes window.

Cancel
Closes without writing.

In SA Mode:

Shows countdown timer.

Buttons: Show Pending, Refresh Data.

Self-Attendance (SA) Mode

Started by:
/att ls sa {alias}
/att ls2 sa {alias}
OR via /attend with Self Attest enabled.

Behavior:

Builds roster from the event’s zone, not your zone.

Host is always marked present, even if not in the event zone.

Other players in the event zone start as “X Name” (pending confirmation).

Chat confirmations (in LS):
!here
!present
!herebrother
Removes the X prefix.

Manual opt-in:
!addme
Adds the sender even if not in the event zone.

SA ends automatically:

When the timer from satimers.txt expires.

Automatically writes CSV and sends LS message.

CSV Output

Writes one line per confirmed attendee in:
Name,MainJob,Date,Time,Zone,EventName

Saved inside either:
HNM Logs/
Event Logs/

Example filename:
Monday 23 January 2025 12.34.56.csv