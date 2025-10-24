Attendance Addon (att)
======================
Author: literallywho, Nils  
Version: 3.0 

A Final Fantasy XI Ashita v4 addon that takes attendance of players (alliance-based or zone-based), provides a GUI to review/remove entries, and writes the final roster to a CSV file. It can optionally send a linkshell (LS) message announcing that attendance was taken for either an HNM or an Event.

---------------------------------------
1. Installation
---------------------------------------
1. Obtain the addon:
   - Place the entire "att" folder inside your Ashita v4 "addons" directory.
   - Inside the "att" folder, you should see "att.lua" plus a "resources" folder containing several CSV/TXT files (e.g. jobs.csv, zones.csv, shortnames.txt, creditnames.txt).

2. Required Files:
   - att.lua – The main addon code.
   - resources/jobs.csv – Lists job IDs → job names.
   - resources/zones.csv – Lists zone IDs → zone names.
   - resources/shortnames.txt – Alias → full event name pairs.
   - resources/creditnames.txt – Defines which zones count for each event name.

3. Load the addon:
   - Place "att" in your Ashita addons folder.
   - Either add it to scripts/default.txt or manually load it in-game via:
     /addon load att

---------------------------------------
2. Files and Folders
---------------------------------------
- att.lua
  Main addon script.

- resources/
  - jobs.csv
    Used to look up main/sub job names by ID.
  - zones.csv
    Used to look up zone names by ID.
  - shortnames.txt
    Contains lines: "alias,Full Event Name" (e.g. aspi,Aspidochelone).
  - creditnames.txt
    Each line: "Full Event Name,Zone Name" (e.g. Aspidochelone,Valley of Sorrows).
    Tells the addon which zones grant credit for each named event/HNM.

- Log Folders:
  - Event Logs/ – Attendance CSVs for events.
  - HNM Logs/ – Attendance CSVs for HNMs.


---------------------------------------
3. Usage Overview
---------------------------------------
**New command**
1) Attend
   - /attend will bring up a gui for taking attendance
   - These buttons will allow for attendance of various things defined in the creditnames file - they will automatically search, then grab names

Main Command: /att

1) No arguments:
   - Gathers attendance from your party/alliance only.
   - Defaults to HNM mode, but you can switch to Event mode in the GUI if you like.

2) Optional arguments:

   - ls
     /att ls
     Gathers attendance from all players in range (zone-based) rather than alliance-based.

   - Short Alias
     /att aspi
     If "aspi" exists in shortnames.txt, sets the event name to that full name (e.g. "Aspidochelone").
     Otherwise defaults to "Current Zone".

3) Help Command:
	 /att help
     Opens a Help Window listing all short aliases that would apply to your current zone.

---------------------------------------
4. The ImGui Interface
---------------------------------------
After running a valid /att command (e.g. /att, /att ls, /att aspi), the addon:

- Collects attendee data (alliance-based or zone-based).
- Opens a window titled "Attendance Results."

Inside this window:
- Mode Selection (Radio Buttons):
  - HNM (default)
  - Event
  Determines which folder the CSV is saved to (HNM Logs or Event Logs) and which LS message is sent.
- Event Name Display:
  Shows whichever event name was resolved (from short alias or "Current Zone").
- Attendee List:
  Name, Zone, Main/Sub Job. Each entry has a "Remove" button if you want to exclude them.
- Final Buttons:
  - Write & Close:
    Writes the CSV file and sends the LS message if one was determined.
    Closes the GUI window.
  - Cancel:
    Closes without writing or sending any message.

If you click [X] to close the window, it's the same as Cancel.


---------------------------------------
5. File Output
---------------------------------------
When you click "Write & Close," one line per attendee is written:
Name,MainJob,Date,Time,Zone,EventName

Example CSV filenames:
- HNM Logs/Monday 23 January 2025 12.34.56.csv
- Event Logs/Monday 23 January 2025 12.34.56.csv

---------------------------------------
6. Customizing Short Names and Credit Zones
---------------------------------------
shortnames.txt
   - Defines "alias,Full Event Name" pairs, e.g. aspi,Aspidochelone
creditnames.txt
   - Defines "Full Event Name,Zone Name", e.g. Aspidochelone,Valley of Sorrows

Thus, if you do /att aspi, only those in "Valley of Sorrows" (for Aspidochelone) are included.

---------------------------------------
7. Examples
---------------------------------------
1) /att
   Alliance-based, no short alias → defaults to "Current Zone" with GUI in HNM mode.
2) /att aspi
   Alliance-based, short alias "aspi" → event name is "Aspidochelone" (if found).
3) /att ls
   Zone-based, no short alias → "Current Zone" is used, HNM mode by default.
4) /att ls aspi
   Zone-based, short alias "aspi" → "Aspidochelone" in zone-based gather.
5) /att help
   Shows short aliases valid for your current zone in a separate Help Window.