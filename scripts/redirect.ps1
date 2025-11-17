param(
    [Parameter(Mandatory=$true)][string]$StartUrl,
    [int]$MaxHops = 10,
    [string]$UserAgent = $env:FORUM_UA
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

function Resolve-FinalUrl {
    param([string]$StartUrl,[int]$MaxHops,[string]$UserAgent)

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client  = New-Object System.Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.Clear()
    $client.DefaultRequestHeaders.Add("User-Agent",$UserAgent)

    $current = $StartUrl
    Write-Host "DEBUG: redirect-start url=[$current]"
    for ($i=1; $i -le $MaxHops; $i++) {
        $resp = $client.GetAsync($current).Result
        $status = [int]$resp.StatusCode
        Write-Host "DEBUG: hop#$i status=[$status]"
        if ($resp.Headers.Location) {
            $locAbs = if ($resp.Headers.Location.IsAbsoluteUri) { 
                $resp.Headers.Location.AbsoluteUri 
            } else { 
                ([System.Uri]::new($current,$resp.Headers.Location.ToString())).AbsoluteUri 
            }
            Write-Host "DEBUG: hop#$i Location=[$locAbs]"
            $current = $locAbs
            continue
        } else {
            Write-Host "DEBUG: hop#$i no Location → final=[$current]"
            return $current
        }
    }
    Write-Host "DEBUG: redirect-end final=[$current]"
    return $current
}

# Thực thi
$final = Resolve-FinalUrl -StartUrl $StartUrl -MaxHops $MaxHops -UserAgent $UserAgent
Write-Output $final
