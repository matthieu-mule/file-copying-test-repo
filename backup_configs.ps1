# See scripts_tests.txt file for all script tests conducted.

<#
.SYNOPSIS
    Syncs config files between the Public runtime folder and the User's Git Repo.
.DESCRIPTION
    - PUSH: Detects New, Modified, AND Deleted files in Public. 
            User selects changes via GUI to apply to Repo.
    - PULL: Fetches/Checkouts specific branch, Pulls, then overwrites Public folder.
.PARAMETER Mode
    'Push' (Public -> Repo) or 'Pull' (Repo -> Public)
#>
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("push", "pull")]
    [string]$Mode
)

# --- CONFIGURATION ---
$PublicPath = "C:\Users\Public\config_files"
$RepoPath   = "C:\Users\$($env:USERNAME)\file-copying-test-repo"
$Branch     = "main"  # Define your target branch here

# --- MAIN LOGIC ---

Write-Host "Running in [$Mode] mode..." -ForegroundColor Cyan

# ==========================================
#                PULL MODE
# ==========================================
if ($Mode -eq "pull") {

    # --- PRE-CHECK: SCAN FOR UN-PUSHED LOCAL CHANGES ---
    Write-Host "Checking for local changes before pulling..." -ForegroundColor Cyan
    $UnsavedFiles = @()

        if (Test-Path $PublicPath) {
            $PublicFiles = Get-ChildItem -Path $PublicPath -Recurse -File
            
            foreach ($pFile in $PublicFiles) {
                $relativePath  = $pFile.FullName.Substring($PublicPath.Length)
                $rFileFullPath = "$RepoPath$relativePath"

                # Check if file is new or modified in Public compared to Repo
                if (-not (Test-Path $rFileFullPath)) {
                    $UnsavedFiles += " [NEW]      $relativePath"
                }
                else {
                    $rFile = Get-Item $rFileFullPath
                    if ($pFile.LastWriteTime -gt $rFile.LastWriteTime) {
                        $UnsavedFiles += " [MODIFIED] $relativePath"
                    }
                }
            }
        }

    # --- SAFETY CONFIRMATION ---
    Write-Host "`n!!! CRITICAL WARNING !!!" -ForegroundColor Red
    
    if ($UnsavedFiles.Count -gt 0) {
        Write-Host "The following files have changes in the Public config files that are NOT in the Repo:" -ForegroundColor Yellow
        foreach ($file in $UnsavedFiles) {
            Write-Host $file -ForegroundColor Yellow
        }
        Write-Host "`nIf you pull now, these changes will be OVERWRITTEN and LOST." -ForegroundColor Red
    }
    else {
        Write-Host "No local changes detected. However, proceed with caution." -ForegroundColor Gray
        Write-Host "Are you sure you want to overwrite Public files with Repo files? Rename these files, or push them to the git repo before pulling." -ForegroundColor Red
    }

    Write-Host "------------------------------------------------------------" -ForegroundColor Red
    $Confirm = Read-Host "Type 'y' to continue (Overwrite Public), or anything else to cancel"
    
    if ($Confirm -ne "y") {
        Write-Host "Operation cancelled by user. No files were changed." -ForegroundColor Green
        exit
    }
    # ---------------------------

    Write-Host "Step 1: Updating Git Repo..." -ForegroundColor Yellow
    Set-Location $RepoPath
    
    # 1. Fetch
    Write-Host " > Git Fetch..."
    git fetch
    
    # 2. Checkout
    Write-Host " > Checkout $Branch..."
    git checkout $Branch
    
    # 3. Pull
    Write-Host " > Git Pull..."
    git pull

    Write-Host "Step 2: Syncing to Public Folder..." -ForegroundColor Yellow

    if (Test-Path $RepoPath) {
        # Get all items in Repo EXCEPT the .git folder
        $RepoItems = Get-ChildItem -Path $RepoPath -Exclude ".git"

        foreach ($item in RepoItems) {
            Write-Host " > Syncing $($item.Name)..."
            # Copy to Public (Create Public root if missing)
            if (-not (Test-Path $PublicPath)) { New-Item -ItemType Directory -Path $PublicPath | Out-Null }

            Copy-Item -Path $item.FullName -Destination $PublicPath -Recurse -Force
        }
    }

    Write-Host "Public folder updated successfully." -ForegroundColor Green
}

# ==========================================
#                PUSH MODE
# ==========================================
if ($Mode -eq "push") {
    Write-Host "Step 1: Scanning for changes..." -ForegroundColor Yellow
    
    $ChangesList = @()

        # A. Check for NEW or MODIFIED files (Scan Public)
        if (Test-Path $PublicPath) {
            $PublicFiles = Get-ChildItem -Path $PublicPath -Recurse -File
            
            foreach ($pFile in $PublicFiles) {
                $relativePath  = $pFile.FullName.Substring($PublicPath.Length)
                $rFileFullPath = "$RepoPath$relativePath"
                
                $reason = ""

                if (-not (Test-Path $rFileFullPath)) {
                    $reason = "New File"
                }
                else {
                    $rFile = Get-Item $rFileFullPath
                    # Compare timestamps (Public is newer)
                    if ($pFile.LastWriteTime -gt $rFile.LastWriteTime) {
                        $reason = "Modified (Public is Newer)"
                    }
                }

                if ($reason) {
                    $ChangesList += [PSCustomObject]@{
                        Action     = "Copy to Repo"
                        Reason     = $reason
                        File       = $relativePath
                        SourcePath = $pFile.FullName
                        DestPath   = $rFileFullPath
                    }
                }
            }
        }

        # B. Check for DELETED files (Scan Repo)
        if (Test-Path $RepoPath) {
            $RepoFiles = Get-ChildItem -Path $RepoPath -Recurse -File | Where-Object { $_.FullName -notmatch '\\.git\\' }
            
            foreach ($rFile in $RepoFiles) {
                $relativePath  = $rFile.FullName.Substring($RepoPath.Length)
                $pFileFullPath = "$PublicPath$relativePath"

                if (-not (Test-Path $pFileFullPath)) {
                    $ChangesList += [PSCustomObject]@{
                        Action     = "Delete from Repo"
                        Reason     = "Deleted in Public"
                        File       = $relativePath
                        SourcePath = $rFile.FullName # Valid path to delete
                        DestPath   = "N/A"
                    }
                }
            }
        }

    if ($ChangesList.Count -eq 0) {
        Write-Host "No changes detected." -ForegroundColor Green
        exit
    }

    # Step 2: Show GUI
    Write-Host "Opening selection window..."
    $Selected = $ChangesList | Out-GridView -Title "Select changes to sync to Repo (Ctrl+Click for multiple)" -PassThru

    if ($Selected) {
        # Step 3: Execute Actions
        foreach ($item in $Selected) {
            if ($item.Action -eq "Copy to Repo") {
                # Handle Directory creation
                $destDir = Split-Path $item.DestPath
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
                
                Copy-Item -Path $item.SourcePath -Destination $item.DestPath -Force
                Write-Host " [COPIED]  $($item.File)" -ForegroundColor Gray
            }
            elseif ($item.Action -eq "Delete from Repo") {
                Remove-Item -Path $item.SourcePath -Force
                Write-Host " [DELETED] $($item.File)" -ForegroundColor Red
            }
        }

        # Step 4: Git Commit & Push
        Write-Host "`nSync Complete." -ForegroundColor Cyan
        Set-Location $RepoPath
        git status -s

        $CommitMsg = Read-Host "`nEnter commit message to Push (or press Enter to skip Git steps)"

        if (-not [string]::IsNullOrWhiteSpace($CommitMsg)) {
            Write-Host "Committing and Pushing..." -ForegroundColor Yellow

            # Stage all changes (including deletions)
            # If you are in a subfolder of the git repo it will stage changes to all files in the repo even if 
            # they are in a parent folder
            git add -A

            # Commit
            git commit -m "$CommitMsg"

            # Push to the configured branch
            # This command prevents accidents: it works even if you haven't set an upstream tracking branch yet
            # It also prevents accidents where you might be pushing to the wrong branch
            git push origin $Branch

            Write-Host "Done!" -ForegroundColor Green
        }
        else {
            Write-Host "Skipping Git Commit/Push. Changes are staged/saved locally." -ForegroundColor Gray
        }

    }
    else {
        Write-Host "Operation cancelled by user." -ForegroundColor Red
    }
}
