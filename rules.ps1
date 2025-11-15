param([string]$FileNameA)

$raw = [Environment]::GetEnvironmentVariable("FILE_CODE_RULES")
if ([string]::IsNullOrWhiteSpace($raw)) { return "{}" }

try { $rules = $raw | ConvertFrom-Json } catch { return "{}" }

$matchedRule = $null
foreach ($r in $rules) {
    if ($FileNameA.ToLower() -like $r.Pattern.ToLower()) {
        $matchedRule = $r
        break
    }
}

if ($matchedRule) {
    $matchedRule | ConvertTo-Json -Compress
} else {
    "{}"
}
