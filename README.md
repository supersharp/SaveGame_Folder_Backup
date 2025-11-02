
<img width="979" height="512" alt="pwsh_oC3t6eJZ3i" src="https://github.com/user-attachments/assets/e623658a-3177-4b0b-b9a4-43306f0afdd0" />

# SaveGame_Folder_Backup
Helps to create a scheduled or manual backup of common Save Game Folder locations

**Directories backed up:**
- `C:\Users\Public\Documents`
- `%localappdata%`

**Features:**
Allows adding folders to ignore list to not backup from %localappdata%
Ability to create a Scheduled Task to run every logon to backup the folders
Logs stored at: C:\Save_Game_Backup_Logs

**How to Run the Save Game Backup Script**
=======================================

1.  Double-click the `Run_Save_Game_Backup.bat` file to start the script. (Administrator access required)
2.  The script will open a menu in a PowerShell window. If it's your first time running it, you will be guided through an initial setup process to choose your backup locations.
3.  Follow the on-screen instructions to configure and manage your game save backups.

**Menu Options**
======================

Brief explanation of what each menu option does:

**Option 1: Create/Recreate Logon Backup Scheduled Task**
--------------------------------------------------------
- This option sets up an automatic backup that runs every time you log on to Windows.
- It creates a task in the Windows Task Scheduler that runs the backup in the background.
- This is a "set it and forget it" way to make sure your game saves are always protected.

**Option 2: Restore Data**
--------------------------
- Use this option to copy your backed-up game saves back to their original locations.
- WARNING: This will overwrite any existing local save files with the files from your backup.

**Option 3: Backup Now**
------------------------
- This option allows you to run a backup immediately, without waiting for the next logon.
- It will back up both your `Public Documents` and the selected `AppData` folders.

**Option 4: Add AppData folders to ignore list**
--------------------------------------------------
- Many games and applications store data in the `AppData\Local` folder.
- This script is designed to back up these folders, but you might want to prevent some of them from being backed up (e.g., web browser caches, application settings that aren't games).
- This option shows you a list of folders that are currently being backed up and lets you select folders to add to an "ignore list" (also called an exclusion list). Ignored folders will not be backed up.
- You can input numbers such as: 1,5-6,16-20 (This will select folders 1,5,6,16,17,18,19,20).

**Option 5: Remove AppData folders from ignore list**
-----------------------------------------------------
- This option shows you a list of all the folders you are currently ignoring.
- You can select folders from this list to remove them from the ignore list. Once removed, they will be included in the next backup.
- You can input numbers such as: 1,5-6,16-20 (This will select folders 1,5,6,16,17,18,19,20).

**Option 6: Exit**
------------------
- This will close the backup manager.
