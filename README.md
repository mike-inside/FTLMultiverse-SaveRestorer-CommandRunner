# FTL: Multiverse - Save Restorer and Command Runner

A small utility to automatically back up FTL: Multiverse saves and to run console commands/scripts in-game.

Prerequisites
- FTL (Faster Than Light) installed.
- Multiverse mod installed from https://subsetgames.com/forum/viewtopic.php?t=35332 (look for the "DOWNLOAD INSTALLER" link).

Setting up the program
- Extract the program anywhere you like.
- Run "FTLSaveRestore.exe".
- Verify the "Save Folder" and "Game Exe" paths in the main window and adjust if needed.


## Save Restorer

Using the Save Restorer
- Click the "Launch Game" button to start FTL Multiverse.
- Enable "Automatically launch game" to have the game opened automatically when you run the Save Restorer.
- Load your game or start a new one.
- The Save Restorer runs in the background and makes a backup whenever the game writes its continue save.
- Note a typical run can generate hundreds or thousands of files, I recommend using the "Open Save Folder" button and pruning the backups occasionally, or the save list will take too long to refresh. 

Restoring a previous saved game
- Filter backups using the search box or by Ship name.
- If still in an active game, press Esc and choose Main Menu.
- Select a save set from the left-side list.
  - Clicking a save shows parsed strings from that save (crew, weapons, events etc) to help identify the right backup.
- Click "Restore Save".
- In-game, click "Continue" to load the restored save.
- By default persistent changes (achievements, ship unlocks, etc.) are not restored. Enable "Restore all" to replace those as well.


## Command Runner

Opening the Command Runner
- From the Save Restorer window: click the "Console Commands" button.
- From the system tray: right-click the tray icon and choose "Open Command Editor".

Important command-runner requirements and behavior
- The game must have the in-game Command Window open for Run Script to work. The default key to open the Command Window is `\`.
- You must not have other in-game windows open (for example: event windows, shops, or anything that intercepts keyboard input).

Filtering and searching commands
- Use the Filter text box to search commands by keyword. The search checks command text, category, subcategory, topic/type and description.
- Filters update the command list dynamically as you change them.
- Use the Category, Subcategory and Type dropdowns to narrow the catalog:
  - Selecting a category updates available subcategories.
  - Selecting a subcategory updates available types.
  - Set any dropdown to "All" to include everything.

Adding commands to the script editor
- Double-click any command in the left list to add it to the script editor on the right.
- Double-click inserts the command at the current cursor position in the script editor (if text is selected, the inserted command replaces the selection).
- Scripts can contain comments (lines starting with `;`, `#`, or `//`) and blank lines; they are ignored when running.

Running scripts
- Load or write a script in the editor. Save/load script files using the provided buttons.
- Click "Run Script" to execute the script.
- The runner sends each command line to the game with a short delay between send, Enter, and (optionally) re-opening the command window as needed. Adjust the command delay setting if needed.
- If the script fails to work, verify the Command Window is open in-game and that no other in-game popups are active.


## Legal / Data notes
- Copyright (C) 2025  mikeInside
- Licensed under GPL-3.0-or-later https://www.gnu.org/licenses/gpl-3.0.html
- This program includes a CSV derived from the FTL Multiverse Wiki "List of IDs" (CC BY-SA 4.0). Attribution and share-alike obligations apply for derived data.

Enjoy using the Save Restorer and Command Runner. Report issues through the project repository.
