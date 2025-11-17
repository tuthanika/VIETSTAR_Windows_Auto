param(
    [Parameter(Mandatory=$true)][string]$FileNameA,
    [string]$RulesJson = $env:FILE_CODE_RULES
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RulesJson)) {
    Write-Host "ERROR: rules.ps1 FILE_CODE_RULES env empty"
    Write-Output ""
    exit 1
}

try {
    $rules = $RulesJson | ConvertFrom-Json
} catch {
    Write-Host "ERROR: rules.ps1 invalid JSON"
    Write-Output ""
    exit 1
}

foreach ($r in $rules) {
    if ($null -eq $r.Patterns) { continue }
    foreach ($pat in $r.Patterns) {
        if ([string]::IsNullOrWhiteSpace($pat)) { continue }
        if ($FileNameA.ToLower() -like $pat.ToLower()) {
            Write-Host "DEBUG: rules.ps1 matched pattern=[$pat] ? folder=[$($r.Folder)] for file=[$FileNameA]"
            Write-Output $r.Folder
            exit 0
        }
    }
}

Write-Host "WARN: rules.ps1 no folder rule matched for file=[$FileNameA]"
Write-Output ""
