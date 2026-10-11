<#
.SYNOPSIS
  Generates controlled file events in a folder monitored by the Wazuh agent (FIM) to validate custom rules.

.DESCRIPTION
  1. Creates, modifies and deletes a normal file
       expected: rule 554 (added), 550 (modified), 100005 (deleted)
  2. Creates and deletes an Office-style temporary file (~$...)
       expected: no alerts (rule 100008)
  3. Creates and deletes BurstCount files in a burst
       expected: rule 100009 (level 12)
  Only files whose names start with 'fimtest-' are created and removed.
  Run it on a folder that is monitored in real time by the agent group configuration.

.EXAMPLE
  .\Test-FIM.ps1 -Path 'C:\Users\USER\Documents\CRITICAL_FOLDER_1'
  .\Test-FIM.ps1 -Path 'C:\Users\USER\Documents\CRITICAL_FOLDER_1' -SkipBurst
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateRange(2, 500)][int]$BurstCount = 25,
    [ValidateRange(1, 60)][int]$WaitSeconds = 5,
    [switch]$SkipBurst
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }

$tag     = 'fimtest-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$normal  = Join-Path $Path ($tag + '.txt')
$temp    = Join-Path $Path ('~$' + $tag + '.docx')
$started = (Get-Date).ToUniversalTime().ToString('o')
$marks   = [ordered]@{}
function Mark($name) { $script:marks[$name] = (Get-Date).ToUniversalTime().ToString('o') }

try {
    Write-Host "[$tag] creating a normal file and an Office-style temporary file"
    New-Item -Path $normal -ItemType File | Out-Null
    Mark 'create_normal_file (expect rule 554)'
    New-Item -Path $temp -ItemType File | Out-Null
    Start-Sleep -Seconds $WaitSeconds

    Write-Host "[$tag] modifying the normal file"
    Add-Content -LiteralPath $normal -Value 'fim test'
    Mark 'modify_normal_file (expect rule 550)'
    Start-Sleep -Seconds $WaitSeconds

    Write-Host "[$tag] deleting both files"
    Remove-Item -LiteralPath $normal, $temp -Force
    Mark 'delete_normal_file (expect rule 100005)'
    Start-Sleep -Seconds $WaitSeconds

    if (-not $SkipBurst) {
        Write-Host "[$tag] burst: creating and deleting $BurstCount files"
        $burst = 1..$BurstCount | ForEach-Object { Join-Path $Path ('{0}-b{1}.txt' -f $tag, $_) }
        $burst | ForEach-Object { New-Item -Path $_ -ItemType File | Out-Null }
        Mark 'burst_created'
        Start-Sleep -Seconds $WaitSeconds
        Remove-Item -LiteralPath $burst -Force
        Mark 'burst_deleted (expect rule 100009)'
    }
}
finally {
    # Clean up anything left behind by an interrupted run
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$tag*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Test tag:       $tag"
Write-Host "Started (UTC):  $started"
foreach ($k in $marks.Keys) { Write-Host ("{0,-45} {1}" -f $k, $marks[$k]) }
Write-Host 'Latency = alert @timestamp minus the UTC time of the matching action above.'
Write-Host 'Query the indexer for syscheck.path containing the tag (README.md, section 5).'
