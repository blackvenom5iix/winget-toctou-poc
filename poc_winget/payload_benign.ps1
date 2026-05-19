# BENIGN PAYLOAD - For vulnerability verification purposes only
# This code only writes a proof file - it does not harm the system
$proofFile = "C:\poc_winget\TOCTOU_PROOF_EXECUTED.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
$content = @"
=== TOCTOU PROOF OF CONCEPT ===
Timestamp: $timestamp
This file proves the installer was replaced before execution.
Process: $($PID)
User: $($env:USERNAME)
Integrity: Medium (replaced file ran successfully)
=== END POC ===
"@
$content | Out-File -FilePath $proofFile -Encoding UTF8
Write-Host "Proof written to: $proofFile"
