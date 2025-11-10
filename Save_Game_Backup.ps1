# =============================================
# Save_Game_Backup.ps1 - Self-elevating version
# =============================================

param(
    [string]$Mode
)

# Argument and Mode Debugging
try {
    if (-not (Test-Path 'C:\Save_Game_Backup_Logs')) { New-Item -Path 'C:\Save_Game_Backup_Logs' -ItemType Directory -Force | Out-Null }
    $DebugLogPath = "C:\Save_Game_Backup_Logs\argument_debug.log"
    $logContent = @"
-----------------------------------------
Script started at $(Get-Date)
Working Directory: $(Get-Location)
Command Line: $($MyInvocation.Line)
PSBoundParameters: $($PSBoundParameters | Out-String)
Mode parameter value: [$Mode]
-----------------------------------------
"@
    Add-Content -Path $DebugLogPath -Value $logContent
}
catch {
    # Fail silently if we can't even write to the debug log
}




# Function to check if running as admin
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch as admin if needed, but not in automated mode
if (-not (Test-Admin) -and -not $Mode) {
    Write-Host "Requesting administrative privileges..."
    Start-Process -FilePath pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Force UTF-8 output (important for ASCII art)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Set this script's execution policy for the current process to ensure scheduled task creation works
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
$ver = "0.0.1"
# --- Configuration / Parameters ---
# Allow basic overrides by pre-defining these variables in the global scope before dot-sourcing,
# or change the default values below. This keeps the script interactive-friendly while testable.

# Resolve script directory first
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Only set defaults if not already defined in the global scope (so tests can override)
if (-not (Get-Variable -Name SourcePath -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:SourcePath = "C:\Users\Public\Documents\"
}
# BackupPath and AppDataLocalBackupPath are set by Initialise-BackupPaths
if (-not (Get-Variable -Name TaskName -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:TaskName = "Save_Game_Backup"
}
if (-not (Get-Variable -Name LogDir -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:LogDir = "C:\Save_Game_Backup_Logs"
}

# Initialise default CSV content
$script:DefaultExclusions = @"
"FolderPath","Description"
".gradle","[Default] Gradle build system"
".nuget","[Default] NuGet package manager"
".vscode*","[Default] Visual Studio Code data"
"*.log","[Default] Log files"
"*\Cache*","[Default] Various application caches"
"*\Code Cache\*","[Default] Code caches"
"*\Extensions\*","[Default] Browser extensions"
"*\GPUCache\*","[Default] GPU shader caches"
"*\Service Worker\*","[Default] Service worker caches"
"*\Web Applications\*","[Default] Web application data"
"Activision","[Default] Call of Duty "
"Adobe","[Default] Adobe applications data"
"Alienware","[Default] Alienware application data"
"AMD","[Default] AMD driver components"
"Android","[Default] Android development tools"
"Battle.net","[Default] Battle.net data"
"BattlEye","[Default] Anti-cheat data"
"Blizzard Entertainment","[Default] Blizzard Entertainment data"
"BraveSoftware","[Default] Browser cache and data (not game related)"
"cache","[Default] Various application caches"
"CEF","[Default] CEF framework data"
"cloud-code","[Default] Google Cloud Code data"
"Comms","[Default] Microsoft communications data"
"ConnectedDevicesPlatform","[Default] Windows device connectivity data"
"CrashDumps","[Default] Application crash dumps"
"D3DSCache","[Default] DirectX shader cache (regenerated automatically)"
"Discord","[Default] Discord application data"
"Dropbox*","[Default] Dropbox sync data"
"ElevatedDiagnostics","[Default] Windows diagnostics"
"Embark","[Default] Arc Raiders data"
"Epic Games","[Default] Epic Games application data"
"EpicGamesLauncher","[Default] Epic Games application data"
"Frija","[Default] Samsung Firmware Download application data"
"google-vscode-extension","[Default] Visual Studio Code extensions"
"Google","[Default] Google data"
"Intel","[Default] Intel driver components"
"JetBrains","[Default] JetBrains IDEs data"
"Microsoft","[Default] OS Data (not game related)"
"npm-cache","[Default] Node.js package cache"
"NuGet","[Default] Package manager data"
"NVIDIA Corporation","[Default] NVIDIA driver components"
"NVIDIA","[Default] NVIDIA driver components"
"OO Software","[Default] OShutUp Windows data"
"Opera","[Default] Browser cache and data (not game related)"
"PackageManagement","[Default] Windows package management"
"Packages","[Default] Windows Store apps"
"PeerDistRepub","[Default] Peer Distribution data"
"PeerDistRepublication","[Default] Peer Distribution data"
"pip","[Default] Python package manager"
"PioneerGame","[Default] Arc Raiders data"
"PlaceholderTileLogoFolder","[Default] Placeholder tile logos"
"Plutonium","[Default] Plutonium COD client data"
"Private Internet Access","[Default] PIA VPN data"
"ProcessLasso","[Default] Process Lasso data"
"Programs","[Default] Various program data"
"Publisher","[Default] Windows Store publishers data"
"Publishers","[Default] Windows Store publishers data"
"qBittorrent","[Default] qBittorrent data"
"setup","[Default] Application setup files"
"Slack","[Default] Slack data"
"Spotify","[Default] Spotify data"
"StartAllBack","[Default] StartAllBack data"
"Steam","[Default] Steam client data"
"Temp","[Default] Temporary files"
"ToastNotificationManagerCompat","[Default]  Current size: 6.15 KB"
"UnrealEngine","[Default] Unreal Engine data"
"UnrealEngineLauncher","[Default] Unreal Engine data"
"USOPrivate","[Default] Windows Update data"
"VirtualStore","[Default] Windows VirtualStore data"
"vortex-updater","[Default] Vortex Mod Manager updater data"
"VS Revo Group","[Default] Revo Uninstaller data"
"Wabbajack","[Default] Skyrim mod manager data"
"WhatsApp","[Default] WhatsApp data"
"WindowsStore","[Default] Windows Store data"
"winutil","[Default] Windows utilities data"
"Zoom","[Default] Zoom data"
"DriveBeyondHorizons","[Default] DriveBeyondHorizons data"
"@

# ---------------------

function Initialise-ExclusionList {
    try {
        # Set default file path based on script installation directory
        if (-not (Get-Variable -Name AppDataFoldersFile -Scope Global -ErrorAction SilentlyContinue)) {
            $Global:AppDataFoldersFile = Join-Path $ScriptDir 'appdata_folders.csv'
        }

        # Ensure parent directory exists
        $parentDir = Split-Path -Parent $Global:AppDataFoldersFile
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        # Create default exclusion list if file doesn't exist
        if (-not (Test-Path $Global:AppDataFoldersFile)) {
            $script:DefaultExclusions | Set-Content -Path $Global:AppDataFoldersFile -Force
            Write-Host "Created default game save backup exclusion list at: $($Global:AppDataFoldersFile)" -ForegroundColor Green
            Write-Host "This list excludes common Windows and application folders, focusing on game saves." -ForegroundColor Cyan
            Write-Host "You can edit this file to customize which folders to exclude from backup." -ForegroundColor Cyan
        }
    }
    catch {
        Write-Host "Error initializing exclusion list: $($_.Exception.Message)" -ForegroundColor Red
        throw  # Re-throw the error to be caught by the main error handler
    }
}

# Function to create desktop shortcut
function New-ScriptShortcut {
    param(
        [string]$ScriptPath
    )
    
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Save Games Backup Manager.lnk"
    
    # Create .bat file next to the script
    $batPath = Join-Path (Split-Path $ScriptPath) "Run_Save_Game_Backup.bat"
    $batContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "$ScriptPath"
Exit
"@
    $batContent | Set-Content -Path $batPath -Force
    
    # Create shortcut to the .bat file
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $batPath
    $Shortcut.WorkingDirectory = Split-Path $batPath
    $Shortcut.Description = "Save Games Backup Manager"
    $Shortcut.IconLocation = "powershell.exe,0"
    $Shortcut.Save()
    
    Write-Host "Created desktop shortcut: $shortcutPath" -ForegroundColor Green
}

# Function to perform initial setup and get backup paths from user
function Initialise-BackupPaths {
    # Check both current directory and F:\SaveGames_Backup for existing config
    $currentConfigFile = Join-Path $ScriptDir 'backup_config.json'
    $defaultConfigFile = Join-Path 'F:\SaveGames_Backup' 'backup_config.json'
    $configFile = if (Test-Path $defaultConfigFile) { $defaultConfigFile } else { $currentConfigFile }
    $firstRun = -not (Test-Path $configFile)
    
    # If config exists, load it
    if (-not $firstRun) {
        try {
            # In automated mode, we don't need to write to host
            if (-not $Mode) {
                Write-Host "Loading configuration from: $configFile" -ForegroundColor Gray
            }
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            $Global:BackupPath = $config.BackupPath
            $Global:AppDataLocalBackupPath = $config.AppDataBackupPath
            $Global:ScriptInstallPath = $config.ScriptInstallPath

            # Check if the running script is different from the installed one
            $installedScriptPath = Join-Path $Global:ScriptInstallPath "Save_Game_Backup.ps1"
            if ((Resolve-Path $PSCommandPath).Path -ne (Resolve-Path $installedScriptPath).Path) {
                Write-Host "WARNING: You are running a script from a different location than the configured installation path." -ForegroundColor Yellow
                Write-Host "Running: $PSCommandPath" -ForegroundColor Cyan
                Write-Host "Installed: $installedScriptPath" -ForegroundColor Cyan
                $choice = Read-Host "Do you want to copy this version to the installed location? (This will overwrite the old version) (Y/N)"
                if ($choice -eq 'y' -or $choice -eq 'Y') {
                    try {
                        Copy-Item -Path $PSCommandPath -Destination $installedScriptPath -Force
                        Write-Host "Script successfully copied to $installedScriptPath" -ForegroundColor Green
                        Write-Host "Please re-run the script from its installed location or via a shortcut." -ForegroundColor Yellow
                        exit
                    }
                    catch {
                        Write-Host "ERROR: Could not copy script. Please check permissions." -ForegroundColor Red
                        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
                        exit
                    }
                }
            }
            
            # Update script directory if we've moved
            $ScriptDir = $Global:ScriptInstallPath
            return
        }
        catch {
            Write-Host "Error reading config file. Will create new configuration." -ForegroundColor Yellow
            $firstRun = $true
        }
    }
    
    # Do not run interactive setup in automated mode
    if ($Mode) {
        Write-Host "Error: Backup is not configured. Please run the script without parameters to configure it first." -ForegroundColor Red
        exit 1
    }

    Clear-Host
    Write-Host "=== Initial Setup ===" -ForegroundColor Cyan
    Write-Host "Welcome to Save Games Backup Manager!" -ForegroundColor White
    Write-Host "Let's configure your backup locations." -ForegroundColor White
    Write-Host ""

    try {
        # Default paths
        $defaultPubBackup = "F:\SaveGames_Backup\Public_Documents"
        $defaultAppBackup = "F:\SaveGames_Backup\AppData_Local"
        $defaultScriptPath = "F:\SaveGames_Backup"

        # Get Public Documents backup path
        Write-Host "Step 1: Public Documents Backup Location" -ForegroundColor Yellow
        Write-Host "Default: $defaultPubBackup" -ForegroundColor Gray
        Write-Host "Enter the path where you want to backup Public Documents or press Enter for default:" -ForegroundColor White
        $pubBackup = Read-Host
        if ([string]::IsNullOrWhiteSpace($pubBackup)) {
            $pubBackup = $defaultPubBackup
        }
        
        # Get AppData backup path
        Write-Host "`nStep 2: AppData Local Backup Location" -ForegroundColor Yellow
        Write-Host "Default: $defaultAppBackup" -ForegroundColor Gray
        Write-Host "Enter the path where you want to backup AppData Local folders or press Enter for default:" -ForegroundColor White
        $appBackup = Read-Host
        if ([string]::IsNullOrWhiteSpace($appBackup)) {
            $appBackup = $defaultAppBackup
        }

        # Convert paths to absolute paths
        $pubBackup = [System.IO.Path]::GetFullPath($pubBackup)
        $appBackup = [System.IO.Path]::GetFullPath($appBackup)

        Write-Host "`nVerifying paths..." -ForegroundColor Yellow
        
        # Ask for script installation location
        Write-Host "`nStep 3: Script Installation Location" -ForegroundColor Yellow
        Write-Host "Default: $defaultScriptPath" -ForegroundColor Gray
        Write-Host "Enter the path where you want to install the script or press Enter for default:" -ForegroundColor White
        $scriptPath = Read-Host
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = $defaultScriptPath
        }

        # Convert to absolute path
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)

        Write-Host "`nCreating directories..." -ForegroundColor Yellow
        
        # Validate paths before creating
        $dirsToCreate = @($pubBackup, $appBackup, $scriptPath) | Where-Object { $_ -ne $null -and $_ -ne '' }
        
        if ($dirsToCreate.Count -eq 0) {
            throw "No valid paths provided for directory creation"
        }
        
        foreach ($dir in $dirsToCreate) {
            try {
                if (-not (Test-Path $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                    Write-Host "Created directory: $dir" -ForegroundColor Green
                }
                else {
                    Write-Host "Directory already exists: $dir" -ForegroundColor Gray
                }
            }
            catch {
                throw "Failed to create directory '$dir': $($_.Exception.Message)"
            }
        }

        # Define new file paths with validation
        $newScriptPath = if ($scriptPath) { Join-Path $scriptPath "Save_Game_Backup.ps1" } else { throw "Invalid script installation path" }
        $newCsvPath = if ($scriptPath) { Join-Path $scriptPath "appdata_folders.csv" } else { throw "Invalid CSV path" }
        $newConfigPath = if ($scriptPath) { Join-Path $scriptPath "backup_config.json" } else { throw "Invalid config path" }

        # Validate and save configuration
        if (-not ($pubBackup -and $appBackup -and $scriptPath)) {
            throw "One or more required paths are missing"
        }

        $config = @{
            BackupPath        = $pubBackup
            AppDataBackupPath = $appBackup
            ScriptInstallPath = $scriptPath
        }

        try {
            Write-Host "Saving configuration to: $newConfigPath" -ForegroundColor Yellow
            $config | ConvertTo-Json | Set-Content -Path $newConfigPath -Force
            Write-Host "Configuration saved successfully" -ForegroundColor Green
        }
        catch {
            throw "Failed to save configuration: $($_.Exception.Message)"
        }
        Write-Host "Saved configuration to: $newConfigPath" -ForegroundColor Green
        
        # Set global variables
        $Global:BackupPath = $pubBackup
        $Global:AppDataLocalBackupPath = $appBackup
        $Global:ScriptInstallPath = $scriptPath
        $Global:AppDataFoldersFile = $newCsvPath  # Update the global CSV file path

        Initialise-ExclusionList

        # Copy files to new location if not already there
        if ($MyInvocation.MyCommand.Path -ne $newScriptPath) {
try {
                Write-Host "`nCopying script to new installation path: $newScriptPath" -ForegroundColor Yellow
                
                # Directly copy the currently running script file using elevated privileges
                Copy-Item -Path $PSCommandPath -Destination $newScriptPath -Force

                # Ask about creating desktop shortcut
                Write-Host "`nWould you like to create a desktop shortcut? (Y/N)" -ForegroundColor Yellow
                $createShortcut = Read-Host
                if ($createShortcut -eq 'Y' -or $createShortcut -eq 'y') {
                    try {
                        # Use the new script path for the shortcut
                        New-ScriptShortcut -ScriptPath $newScriptPath
                    }
                    catch {
                        Write-Host "Warning: Could not create shortcut: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "You can create it manually later if needed." -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Host "Error during file copy operation: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Please ensure you have proper permissions and try again." -ForegroundColor Yellow
                exit 1
            }
        }
    }
    catch {
        Write-Host "Error during setup: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please run the script again with administrator privileges if needed." -ForegroundColor Yellow
        exit 1
    }

    # If we get here, no restart was needed (script is already in final location)
    Write-Host "`nPress any key to continue..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# --- Automated Backup Function ---
function Start-AutomatedBackup {
    $DebugLog = Join-Path $LogDir -ChildPath "Save_Game_Backup_DEBUG_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    try {
        # Ensure log directory exists
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

        # Define a single log file path for this run
        $LogFile = Join-Path $LogDir -ChildPath "Save_Game_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        # --- Start Logging ---
        Add-Content -Path $LogFile -Value 'Save Games Backup - Automated Task'
        Add-Content -Path $LogFile -Value ("Started: " + (Get-Date))

        # --- Robocopy Commands ---
        
        # Public Documents
        robocopy $SourcePath $BackupPath /E /MIR /ZB /LOG+:$LogFile /NFL /NDL /NJH /NJS

        # AppData folders
        $AppDataFolders = Get-AppDataFolders
        foreach ($folder in $AppDataFolders) {
            $Source = Join-Path $env:LOCALAPPDATA $folder
            $Dest = Join-Path $AppDataLocalBackupPath $folder
            robocopy $Source $Dest /E /MIR /ZB /LOG+:$LogFile /NFL /NDL /NJH /NJS
        }

        # --- End Logging ---
        Add-Content -Path $LogFile -Value ("Completed: " + (Get-Date))
    }
    catch {
        # Log the error to the debug file
        $_ | Out-String | Add-Content -Path $DebugLog
        $_.ScriptStackTrace | Out-String | Add-Content -Path $DebugLog
    }
}


# --- Utility: parse numeric selections like "1,3-5,7" into an int[] ---
function Get-NumbersFromString {
    param([string]$str)
    
    Write-Host "Debug - Processing input: '$str'" -ForegroundColor Yellow
    
    # Handle empty input
    if ([string]::IsNullOrWhiteSpace($str)) {
        Write-Host "Debug - Empty input" -ForegroundColor Yellow
        return @()
    }
    
    # Clean input - remove brackets and extra spaces
    $cleaned = $str.Trim() -replace '[\[\]]', ''
    Write-Host "Debug - Cleaned input: '$cleaned'" -ForegroundColor Yellow
    
    # Simple case - single number
    if ($cleaned -match '^\d+$') {
        $num = [int]$cleaned
        Write-Host "Debug - Found single number: $num" -ForegroundColor Yellow
        return @($num)
    }
    
    # Handle more complex cases
    $result = @()
    
    foreach ($part in $cleaned -split '[,\s]+') {
        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            if ($end -ge $start) {
                $result += $start..$end
            }
        }
        elseif ($part -match '^\d+$') {
            $result += [int]$part
        }
    }
    
    if ($result.Count -gt 0) {
        Write-Host "Debug - Found numbers: $($result -join ',')" -ForegroundColor Yellow
        return $result | Sort-Object -Unique
    }
    
    Write-Host "Debug - No valid numbers found" -ForegroundColor Yellow
    return @()
}
function Show-UnlistedAppDataFolders {
    Write-Host "`n-- Add Folders to Exclude List (select from existing LOCALAPPDATA) --" -ForegroundColor Yellow

    # Ensure the file exists (create empty if not)
    if (-not (Test-Path $Global:AppDataFoldersFile)) { 
        Initialise-ExclusionList
    }

    $existingObjs = Read-AppDataFile -FilePath $Global:AppDataFoldersFile
    $excluded = $existingObjs | Select-Object -ExpandProperty FolderPath

    # Get top-level directories in LOCALAPPDATA
    try {
        $all = Get-ChildItem -Path $env:LOCALAPPDATA -Directory -ErrorAction Stop | Select-Object -ExpandProperty Name
    }
    catch {
        Write-Host "Failed to enumerate $env:LOCALAPPDATA: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $candidates = $all | Where-Object { $_ -and ($excluded -notcontains $_) } | Sort-Object

    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-Host "All folders under $env:LOCALAPPDATA are already excluded." -ForegroundColor Cyan
        return
    }

    # Display numbered list
    Write-Host "Currently backing up $(if ($candidates.Count -eq $all.Count) { 'all' } else { $candidates.Count }) folders." -ForegroundColor Cyan
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $n = $i + 1
        Write-Host "[$n] $($candidates[$i])"
    }

    while ($true) {
        Write-Host "Enter numbers to exclude from backup (e.g. 1,3-5) or press Enter to cancel:" -ForegroundColor Yellow
        $sel = Read-Host
        if (-not $sel) { Write-Host "Add cancelled." -ForegroundColor Cyan; return }

        # Store raw input before any cleaning
        $rawSel = $sel
        # Clean input thoroughly to ensure proper parsing
        $sel = $sel.Trim() -replace '[\[\]]', '' -replace '\s+', ''
        
        Write-Host "Debug - Raw input: '$sel'" -ForegroundColor Yellow
        
        # Direct function call with the raw input
        $indices = @(Get-NumbersFromString -str $sel)
        
        if ($indices.Count -eq 0) { 
            Write-Host "No valid numbers found in your input." -ForegroundColor Red
            Write-Host "Please enter only numbers and ranges (e.g., 1,3-5)" -ForegroundColor Yellow
            Write-Host "Try again or press Enter to cancel." -ForegroundColor Red
            continue 
        }

        # Validate indices: accept only valid, report invalid
        $validIndices = @()
        $invalidIndices = @()
        foreach ($idx in $indices) {
            if ($idx -ge 1 -and $idx -le $candidates.Count) { $validIndices += $idx }
            else { $invalidIndices += $idx }
        }
        $validIndices = $validIndices | Sort-Object -Unique
        if ($invalidIndices.Count -gt 0 -and $validIndices.Count -gt 0) { Write-Host "Warning: these indexes are out of range and will be ignored: $($invalidIndices -join ', ')" -ForegroundColor Yellow }
        if ($validIndices.Count -gt 0) { break }

        # No valid indexes
        Write-Host "You entered indexes: $($indices -join ', ') but there are only $($candidates.Count) items." -ForegroundColor Yellow
        Write-Host "Press R to retry, or any other key to cancel:" -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -ne 'R' -and $choice -ne 'r') { Write-Host 'Add cancelled.' -ForegroundColor Cyan; return }
    }

    $toAdd = $validIndices | ForEach-Object { $candidates[$_ - 1] }

    # Calculate sizes for preview
    Write-Host "`nPreview: The following entries will be added to excluded folders:" -ForegroundColor Cyan
    foreach ($folder in $toAdd) {
        $path = Join-Path $env:LOCALAPPDATA $folder
        try {
            $size = Get-FolderSize -Path $path
            if ($size -gt 0) {
                $sizeStr = Format-Size -Size $size
                Write-Host " - $folder ($sizeStr)"
            }
            else {
                Write-Host " - $folder (Empty folder)"
            }
        }
        catch {
            Write-Host " - $folder (Could not access folder)" -ForegroundColor Red
        }
    }
    Write-Host "Press Y to confirm and write changes, any other key to cancel:" -ForegroundColor Yellow
    $c = Read-Host
    if ($c -ne 'Y' -and $c -ne 'y') { Write-Host 'Add cancelled.' -ForegroundColor Cyan; return }

    # Create new entries with folder sizes as descriptions
    $newEntries = @()
    foreach ($folder in $toAdd) {
        if ($excluded -notcontains $folder) {
            $path = Join-Path $env:LOCALAPPDATA $folder
            try {
                $size = Get-FolderSize -Path $path
                $description = if ($size -gt 0) {
                    $sizeStr = Format-Size -Size $size
                    "[User] Current size: $sizeStr"
                }
                else {
                    "[User] Empty folder"
                }
                $newEntries += [pscustomobject]@{
                    FolderPath  = $folder
                    Description = $description
                }
            }
            catch {
                $newEntries += [pscustomobject]@{
                    FolderPath  = $folder
                    Description = "[User] Could not access folder"
                }
            }
        }
    }

    # Combine existing and new entries
    $updatedEntries = $existingObjs + $newEntries
    if (Write-AppDataFile -ExcludedFolders $updatedEntries -FilePath $Global:AppDataFoldersFile) {
        Write-Host "`nAdded $($newEntries.Count) folders to exclusion list." -ForegroundColor Green
    }
    else { Write-Host "Failed to update exclusion list." -ForegroundColor Red }
}

function Edit-AppDataFolders {
    Write-Host "`n-- Edit AppData Folders Exclusion List (remove by number to resume backup) --" -ForegroundColor Yellow

    if (-not (Test-Path $Global:AppDataFoldersFile)) { New-Item -Path $Global:AppDataFoldersFile -ItemType File -Force | Out-Null }
    $entries = Read-AppDataFile -FilePath $Global:AppDataFoldersFile

    if (-not $entries -or $entries.Count -eq 0) { Write-Host "No exclusions found - all folders will be backed up." -ForegroundColor Cyan; return }

    # Show excluded folders with current count - filter out comment lines
    $filteredEntries = $entries | Where-Object { -not $_.FolderPath.StartsWith('#') }
    $defaultCount = ($filteredEntries | Where-Object { $_.Description -like "*[Default]*" }).Count
    $userCount = ($filteredEntries | Where-Object { $_.Description -like "*[User]*" }).Count
    Write-Host "Currently excluding $($filteredEntries.Count) folders from backup ($defaultCount default, $userCount user-added):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $entries.Count; $i++) { 
        $n = $i + 1
        $entry = $entries[$i]
        $folderPath = $entry.FolderPath
        $description = if ($entry.Description) { $entry.Description } else { "" }
        
        # Write entry number and folder path in one color
        if ($entry.Description -like "*[User]*") {
            Write-Host -NoNewline "[$n] $folderPath" -ForegroundColor Yellow
        }
        else {
            Write-Host -NoNewline "[$n] $folderPath" -ForegroundColor Gray
        }
        
        # Write description in white if it exists
        if ($description) {
            Write-Host -NoNewline " - " -ForegroundColor DarkGray
            Write-Host $description -ForegroundColor White
        }
        else {
            Write-Host ""  # Just end the line if no description
        }
    }

    while ($true) {
        Write-Host "`nEnter numbers to remove from exclusion list (e.g. 2,4-6) or press Enter to cancel:" -ForegroundColor White
        Write-Host ""
        Write-Host "(Removing folders from this list will RESUME backing them up)" -ForegroundColor Yellow
        $sel = Read-Host
        if (-not $sel) { Write-Host "Edit cancelled." -ForegroundColor Cyan; return }

        Write-Host "Debug - Raw input: '$sel'" -ForegroundColor Yellow
        
        # Direct function call with the raw input
        $indices = @(Get-NumbersFromString -str $sel)
        
        if ($indices.Count -eq 0) { 
            Write-Host "No valid numbers found in your input." -ForegroundColor Red
            Write-Host "Please enter only numbers and ranges (e.g., 1,3-5)" -ForegroundColor Yellow
            Write-Host "Try again or press Enter to cancel." -ForegroundColor Red
            continue 
        }

        # Validate indices
        $validIndices = @()
        $invalidIndices = @()
        foreach ($idx in $indices) {
            if ($idx -ge 1 -and $idx -le $entries.Count) { $validIndices += $idx } else { $invalidIndices += $idx }
        }
        $validIndices = $validIndices | Sort-Object -Unique
        if ($invalidIndices.Count -gt 0 -and $validIndices.Count -gt 0) { Write-Host "Warning: these indexes are out of range and will be ignored: $($invalidIndices -join ', ')" -ForegroundColor Yellow }
        if ($validIndices.Count -gt 0) { break }

        Write-Host "You entered indexes: $($indices -join ', ') but there are only $($entries.Count) items." -ForegroundColor Yellow
        Write-Host "Press R to retry, or any other key to cancel:" -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -ne 'R' -and $choice -ne 'r') { Write-Host 'Edit cancelled.' -ForegroundColor Cyan; return }
    }

    $toRemove = $validIndices | ForEach-Object { $entries[$_ - 1].Value }

    # Preview
    Write-Host "The following will be removed:" -ForegroundColor Cyan
    $toRemove | ForEach-Object { Write-Host " - $_" }
    Write-Host "Press Y to confirm, any other key to cancel:" -ForegroundColor Green
    $c = Read-Host
    if ($c -ne 'Y' -and $c -ne 'y') { Write-Host 'Removal cancelled.' -ForegroundColor Cyan; return }

    # Filter out the removed entries
    $newEntries = $entries | Where-Object { $toRemove -notcontains $_.FolderPath }
    
    if (Write-AppDataFile -ExcludedFolders $newEntries -FilePath $Global:AppDataFoldersFile) {
        Write-Host "Removed $($toRemove.Count) entries." -ForegroundColor Green
    }
    else { Write-Host "Failed to update file." -ForegroundColor Red }
}



# Function to clean up old log files
function Remove-OldLogFiles {
    param(
        [int]$DaysToKeep = 7
    )
    
    if (-not (Test-Path $LogDir)) {
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
    $oldLogs = Get-ChildItem -Path $LogDir -Filter "$TaskName*.log" |
    Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    if ($oldLogs) {
        Write-Host "Removing log files older than $DaysToKeep days..." -ForegroundColor Yellow
        $oldLogs | ForEach-Object {
            Remove-Item -Path $_.FullName -Force
            Write-Host "Removed: $($_.Name)" -ForegroundColor Gray
        }
    }
}

# --- Core Robocopy Commands ---

# Command to be executed by the scheduled task (Backup: Source -> BackupPath)
# NOTE: This command is now only used for MANUAL backup (Option 3).
# The scheduled task action has a separate, escaped command string in Create-ScheduledTask.
# /E: Subdirectories /MIR: Mirror /ZB: Restartable/Backup mode /LOG: Log to a file
# /NFL /NDL /NJH /NJS: Silent logging flags to prevent excessive console popups in scheduled task
# $BackupCommand = "robocopy `"$SourcePath`" `"$BackupPath`" /E /MIR /ZB /LOG:`"$LogDir\$TaskName_$(Get-Date -Format 'yyyyMMdd_HHmmss').log`" /NFL /NDL /NJH /NJS"

# Command for the manual restore (Restore: BackupPath -> SourcePath)
# /E: Subdirectories /MIR: Mirror /ZB: Restartable/Backup mode
$RestoreCommand = "robocopy `"$BackupPath`" `"$SourcePath`" /E /MIR /ZB"

# --- Functions ---

### AppData file read/write helpers that preserve comments & blank lines and accept CSV or TXT.
function Read-AppDataFile {
    param(
        [string]$FilePath = $Global:AppDataFoldersFile
    )

    # Return an array of objects with FolderPath and Description
    $excluded = @()
    if (-not (Test-Path $FilePath)) { return $excluded }

    try {
        # Skip first line (header)
        $csv = Import-Csv -Path $FilePath
        foreach ($entry in $csv) {
            # Skip comment lines and empty lines
            if (-not [string]::IsNullOrWhiteSpace($entry.FolderPath) -and -not $entry.FolderPath.StartsWith('#')) {
                $excluded += [pscustomobject]@{
                    FolderPath  = $entry.FolderPath.Trim()
                    Description = $entry.Description
                }
            }
        }
    }
    catch {
        Write-Host "Error reading CSV file: $($_.Exception.Message)" -ForegroundColor Red
    }
    return $excluded
}

function Write-AppDataFile {
    param(
        [array]$ExcludedFolders,
        [string]$FilePath = $Global:AppDataFoldersFile
    )
    
    try {
        # Ensure we have Description field, use empty string if missing
        $entries = $ExcludedFolders | ForEach-Object {
            if ($_ -is [string]) {
                [pscustomobject]@{
                    FolderPath  = $_
                    Description = ""
                }
            }
            else {
                $_
            }
        } | Sort-Object FolderPath
        
        # Create CSV content with header
        $entries | Select-Object FolderPath, Description | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
        return $true
    }
    catch {
        Write-Host "Failed to write $FilePath : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-AppDataFolders {
    param(
        [string]$FilePath = $Global:AppDataFoldersFile
    )
    # Get list of excluded folders
    $excluded = Read-AppDataFile -FilePath $FilePath
    $excludedPaths = $excluded | Select-Object -ExpandProperty FolderPath

    # Get all top-level folders in LocalAppData
    try {
        $allFolders = Get-ChildItem -Path $env:LOCALAPPDATA -Directory | Select-Object -ExpandProperty Name
    }
    catch {
        Write-Host "Failed to enumerate $env:LOCALAPPDATA: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }

    # Filter out excluded folders (support wildcards)
    $includedFolders = $allFolders | Where-Object {
        $folder = $_
        $shouldInclude = $true
        foreach ($excludePattern in $excludedPaths) {
            if ($folder -like $excludePattern) {
                $shouldInclude = $false
                break
            }
        }
        return $shouldInclude
    } | Sort-Object
    return $includedFolders
}

function Get-TaskStatus {
    # Check if the task exists and return its state (e.g., Ready, Running, Disabled)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        # The .State property shows the current status, correctly interpolated
        return "Created ($($task.State))"
    }
    else {
        return "Missing"
    }
}

function Get-FolderSize {
    param(
        [string]$Path
    )
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $size) { return 0 }
        return $size
    }
    catch {
        return 0
    }
}

function Format-Size {
    param(
        [long]$Size
    )
    switch ($Size) {
        { $_ -ge 1TB } { "{0:N2} TB" -f ($Size / 1TB); break }
        { $_ -ge 1GB } { "{0:N2} GB" -f ($Size / 1GB); break }
        { $_ -ge 1MB } { "{0:N2} MB" -f ($Size / 1MB); break }
        { $_ -ge 1KB } { "{0:N2} KB" -f ($Size / 1KB); break }
        default { "$Size bytes" }
    }
}

function Show-BackupSummary {
    Write-Host "`n-- Backup Size Summary --" -ForegroundColor Yellow

    # Calculate Public Documents size
    $pubDocSize = Get-FolderSize -Path $SourcePath
    Write-Host "Public Documents: $(Format-Size $pubDocSize)" -ForegroundColor Cyan

    # Calculate AppData sizes
    $includedFolders = Get-AppDataFolders
    $excludedFolders = Read-AppDataFile | Where-Object { $_.Type -eq 'Entry' } | Select-Object -ExpandProperty Value

    $includedSize = 0
    foreach ($folder in $includedFolders) {
        $path = Join-Path $env:LOCALAPPDATA $folder
        $size = Get-FolderSize -Path $path
        $includedSize += $size
    }

    $excludedSize = 0
    foreach ($folder in $excludedFolders) {
        $path = Join-Path $env:LOCALAPPDATA $folder
        $size = Get-FolderSize -Path $path
        $excludedSize += $size
    }

    Write-Host "`nAppData Status:" -ForegroundColor Cyan
    Write-Host "Included: $($includedFolders.Count) folders ($(Format-Size $includedSize))" -ForegroundColor Green
    Write-Host "Excluded: $($excludedFolders.Count) folders ($(Format-Size $excludedSize))" -ForegroundColor Yellow

    $totalSize = $pubDocSize + $includedSize
    Write-Host "`nTotal Backup Size: $(Format-Size $totalSize)" -ForegroundColor Green
    Write-Host "Total Space Saved by Exclusions: $(Format-Size $excludedSize)" -ForegroundColor Yellow
}

function Get-LastBackupDate {
    $LogDir = "C:\Save_Game_Backup_Logs"
    if (-not (Test-Path $LogDir)) {
        return "N/A (Log directory missing)"
    }

    # Find the newest log file based on its write time.
    # This checks both regular and manual backup logs
    $LatestLog = Get-ChildItem -Path $LogDir -Filter "$TaskName*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($LatestLog) {
        # Try to parse the timestamp from the filename
        # This regex looks for the date/time stamp (e.g., 20251101_153000) at the VERY END of the filename.
        if ($LatestLog.BaseName -match ".*(\d{8})_(\d{6})") {
            $DateString = $Matches[1]
            $TimeString = $Matches[2]
            
            try {
                $DateTime = [datetime]::ParseExact("$DateString$TimeString", "yyyyMMddHHmmss", $null)
                # We consider the "LastWriteTime" of the log file to be the most accurate "end time"
                return $LatestLog.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
            catch {
                # Fallback if date parsing fails, but this shouldn't happen if regex matches
                return "Found log, but date unreadable: $($LatestLog.BaseName)"
            }
        }
        else {
            return "Found log, but name format unknown: $($LatestLog.BaseName)"
        }
    }

    return "N/A (No log files found)"
}


function Create-ScheduledTask {
    Write-Host "`n-- Option 1: Create/Recreate Scheduled Task --" -ForegroundColor Yellow

    # Check if the task already exists and ask to recreate
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host "The scheduled task '$TaskName' already exists." -ForegroundColor Cyan
        $choice = Read-Host "Do you want to delete it and create a new one? (Y/N)"
        if ($choice -ne 'y' -and $choice -ne 'Y') {
            Write-Host "Task creation cancelled." -ForegroundColor Cyan
            return
        }
        
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Existing task deleted." -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR: Could not delete existing task. Please remove it manually from Task Scheduler." -ForegroundColor Red
            return
        }
    }

    # 1. Define the action to run the script in automated mode
    $ScriptPathForTask = Join-Path $Global:ScriptInstallPath "Save_Game_Backup.ps1"
    $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPathForTask`" -Mode AutomatedBackup"

    # 2. Define the trigger (At user logon)
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    # 3. Define the settings (Run with highest privileges, which is necessary for Robocopy)
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    # 4. Register the task
    try {
        Write-Host "Attempting to register automatic backup task '$TaskName'..."
        Write-Host "The scheduled task will be configured to run the following script:" -ForegroundColor Yellow
        Write-Host $ScriptPathForTask -ForegroundColor Cyan

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null
        
        Write-Host "`nSUCCESS: Save games backup task created!" -ForegroundColor Green
        Write-Host "It will automatically back up your save games when '$($env:USERNAME)' logs on." -ForegroundColor Green
        Write-Host "Backup logs will be created in '$LogDir'."
        Write-Host "If issues persist, a debug log will be created at '$LogDir\Save_Game_Backup_DEBUG_... .log'" -ForegroundColor Yellow
    }
    catch {
        Write-Host "`nFATAL ERROR: Could not create scheduled task." -ForegroundColor Red
        Write-Host "Please ensure you run this script with Administrator privileges." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Restore-Data {
    Write-Host "`n-- Option 2: Restore Data --" -ForegroundColor Yellow

    # Safety check before restoring
    if (-not (Test-Path $BackupPath -PathType Container)) {
        Write-Host "ERROR: Backup source directory not found at '$BackupPath'. Cannot restore." -ForegroundColor Red
        return
    }

    Write-Host "Source for Restore: $BackupPath"
    Write-Host "Destination (Original Path): $SourcePath"
    Write-Host "WARNING: This operation will copy files from the backup path back to the original location and OVERWRITE any files that are different." -ForegroundColor Red
    Write-Host "Are you sure you want to proceed? (Y/N)" -ForegroundColor White

    $Confirm = Read-Host
    if ($Confirm -ne "Y" -and $Confirm -ne "y") {
        Write-Host "Restore cancelled." -ForegroundColor Cyan
        return
    }

    Write-Host "Starting restoration now..." -ForegroundColor Green
    try {
        # Execute the reverse Robocopy command
        Invoke-Expression $RestoreCommand

        Write-Host "`nRESTORATION COMPLETE." -ForegroundColor Green
        Write-Host "The contents of '$BackupPath' have been mirrored back to '$SourcePath'." -ForegroundColor Green
    }
    catch {
        Write-Host "`nRESTORATION FAILED. Check permissions or file locks." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Backup-DataNow {
    Write-Host "`n-- Option 3: Manual Backup Now --" -ForegroundColor Yellow

    # Safety check
    if (-not (Test-Path $SourcePath -PathType Container)) {
        Write-Host "ERROR: Source directory not found at '$SourcePath'. Cannot perform backup." -ForegroundColor Red
        return
    }
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    
    Write-Host "Source: $SourcePath"
    Write-Host "Destination: $BackupPath"
    Write-Host "Starting savegames backup (Mirror: Source -> Destination)..." -ForegroundColor Green
    
    try {
        # Clean up old log files first
        Remove-OldLogFiles -DaysToKeep 7
        
        # Define a log file specific to the manual run
        $LogFile = "$LogDir\$($TaskName)_Manual_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Write-Host "A detailed log will also be saved to: $LogFile"
        
        # Command for manual run (verbose output to console: /V /TS /FP)
        $ManualRobocopyCommand = "robocopy `"$SourcePath`" `"$BackupPath`" /E /MIR /ZB /V /TS /FP /LOG:`"$LogFile`""
        
        Invoke-Expression $ManualRobocopyCommand
        
        $RobocopyExitCode = $LASTEXITCODE

        if ($RobocopyExitCode -le 7) {
            Write-Host "`nBACKUP COMPLETE (Robocopy Exit Code: $RobocopyExitCode)." -ForegroundColor Green
        }
        else {
            Write-Host "`nBACKUP COMPLETED WITH WARNINGS/ERRORS (Robocopy Exit Code: $RobocopyExitCode). Check the log file for details." -ForegroundColor Red
        }

        # Now back up selected %LOCALAPPDATA% folders
        $AppDataFolders = Get-AppDataFolders
        if ($AppDataFolders.Count -gt 0) {
            Write-Host "`nStarting AppData folders backup..." -ForegroundColor Cyan
            foreach ($folder in $AppDataFolders) {
                $Source = Join-Path $env:LOCALAPPDATA $folder
                $Dest = Join-Path $AppDataLocalBackupPath $folder

                if (-not (Test-Path $Source -PathType Container)) {
                    Write-Host "SKIP: Source folder does not exist: $Source" -ForegroundColor Yellow
                    continue
                }

                # Ensure the destination parent exists
                $destParent = Split-Path $Dest -Parent
                if (-not (Test-Path $destParent)) { New-Item -Path $destParent -ItemType Directory -Force | Out-Null }

                Write-Host "Backing up '$Source' -> '$Dest'"

                # Append this folder's backup log to the main log file
                Add-Content -Path $LogFile -Value "`n`n-- Backing up: $folder --`n"
                $ManualAppCmd = "robocopy `"$Source`" `"$Dest`" /E /MIR /ZB /V /TS /FP /LOG+:`"$LogFile`""
                Invoke-Expression $ManualAppCmd

                $AppExit = $LASTEXITCODE
                if ($AppExit -le 7) {
                    Write-Host "AppData folder '$folder' backup complete (Exit Code: $AppExit)." -ForegroundColor Green
                }
                else {
                    Write-Host "AppData folder '$folder' backup completed with warnings/errors (Exit Code: $AppExit)." -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "No AppData folders currently excluded in '$AppDataFoldersFile'. Backing up all folders." -ForegroundColor Yellow
        }

    }
    catch {
        Write-Host "`nBACKUP FAILED. Check permissions or file locks." -ForegroundColor Red
        Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    }
}
$ver
$asciiart = @"
███████╗ █████╗ ██╗   ██╗███████╗     ██████╗  █████╗ ███╗   ███╗███████╗                                     $ver
██╔════╝██╔══██╗██║   ██║██╔════╝    ██╔════╝ ██╔══██╗████╗ ████║██╔════╝                                   © Tahir
███████╗███████║██║   ██║█████╗      ██║  ███╗███████║██╔████╔██║█████╗                                            
╚════██║██╔══██║╚██╗ ██╔╝██╔══╝      ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝                                            
███████║██║  ██║ ╚████╔╝ ███████╗    ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗                                          
╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝     ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝                                          
                                                                                                                   
██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗     ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗ 
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝    ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝     ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║         ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
"@                                                                                                                   
function Show-Menu {
    Clear-Host
    
    # Get the status for the menu display

    $TaskStatus = Get-TaskStatus
    $LastBackup = Get-LastBackupDate
    Write-Host $asciiart -ForegroundColor Cyan
    # Calculate sizes for display
    $sourceSize = if (Test-Path $SourcePath) { Get-FolderSize -Path $SourcePath } else { 0 }
    $backupSize = if (Test-Path $BackupPath) { Get-FolderSize -Path $BackupPath } else { 0 }
    $appDataSize = if (Test-Path $AppDataLocalBackupPath) { Get-FolderSize -Path $AppDataLocalBackupPath } else { 0 }
    
    Write-Host "  Source Path: $SourcePath" -NoNewline -ForegroundColor Gray
    Write-Host " ($(Format-Size $sourceSize))" -ForegroundColor Green
    
    Write-Host "  Backup Path: $BackupPath" -NoNewline -ForegroundColor Gray
    Write-Host " ($(Format-Size $backupSize))" -ForegroundColor Green
    
    Write-Host "  AppData Backup Path: $AppDataLocalBackupPath" -NoNewline -ForegroundColor Gray
    Write-Host " ($(Format-Size $appDataSize))" -ForegroundColor Green
    
    Write-Host "  AppData folders list: $AppDataFoldersFile" -ForegroundColor Gray
    Write-Host "  Task Name: $TaskName" -ForegroundColor Gray
    Write-Host "  Last Successful Backup: $LastBackup" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "1. Create/Recreate Logon Backup Scheduled Task (Status: $TaskStatus)" -ForegroundColor Yellow
    Write-Host "2. Restore (Copy Backup to Source and Overwrite)" -ForegroundColor Green
    Write-Host "3. Backup Now (Public Documents + AppData folders)" -ForegroundColor Cyan
    Write-Host "4. Add AppData folders to ignore list" -ForegroundColor Cyan
    Write-Host "5. Remove AppData folders from ignore list" -ForegroundColor Cyan
    Write-Host "6. Exit" -ForegroundColor Red
    Write-Host ""
    Write-Host "----------------------------------------------"
    $Choice = Read-Host "Select an option (1-6)"
    return $Choice
}

# --- Main Application Logic ---

# Initialise backup paths and exclusion list at startup
try {
    # Set initial CSV file path before any operations
    if (-not (Get-Variable -Name AppDataFoldersFile -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:AppDataFoldersFile = Join-Path $ScriptDir 'appdata_folders.csv'
    }

    Initialise-BackupPaths    # Initialise paths first to get the final installation location
    
    # Update CSV path to new location if script was moved
    $Global:AppDataFoldersFile = Join-Path $Global:ScriptInstallPath 'appdata_folders.csv'
    
    # Ensure the exclusion list exists at the correct path
    Initialise-ExclusionList

}
catch {
    Write-Host "Error during initialization: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.Exception.StackTrace -ForegroundColor Yellow
    exit 1
}


if ($Mode -eq 'AutomatedBackup') {
    Start-AutomatedBackup
}
else {
    # --- Main Application Loop ---
    do {
        $UserChoice = Show-Menu

        switch ($UserChoice) {
            "1" { Create-ScheduledTask }
            "2" { Restore-Data }
            "3" { Backup-DataNow }
            "4" { Show-UnlistedAppDataFolders }
            "5" { Edit-AppDataFolders }
            "6" { Write-Host "Exiting manager. Goodbye!" -ForegroundColor Red; break }
            default { Write-Host "`nInvalid choice. Please select 1-6." -ForegroundColor Red }
        }
        
        # Updated check for returning to the menu
        if ($UserChoice -ne "8") {
            Write-Host "`nPress any key to return to the menu..."
            $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        }

    } while ($true)
}


# --- End of Script ---
