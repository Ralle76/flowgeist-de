# Property of Ralf Carsjens - flowgeist-de - ISO 27001 Compliant
# dns-switch.ps1 — Point flowgeist.de (+www) at GitHub Pages via the NEW
# Hetzner DNS API (api.hetzner.cloud — zones migrated from dns.hetzner.com).
# Token: $env:HETZNER_API_TOKEN (loaded from global_secrets.env).
# Usage: ./dns-switch.ps1 [-WhatIf] [-Revert]
#   -WhatIf : dry-run, prints planned changes only
#   -Revert : restore @ A + www A to the Hetzner VPS (178.104.2.252)

param(
  [switch]$WhatIf,
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'

if (-not $env:HETZNER_API_TOKEN) {
  Get-Content "$env:USERPROFILE\CascadeProjects\global_secrets.env" | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim('"').Trim("'"))
    }
  }
}
if (-not $env:HETZNER_API_TOKEN) { throw "HETZNER_API_TOKEN not set" }

$headers = @{ Authorization = "Bearer $($env:HETZNER_API_TOKEN)"; 'Content-Type' = 'application/json' }
$zone = 'flowgeist.de'
$base = "https://api.hetzner.cloud/v1/zones/$zone/rrsets"

$GITHUB_PAGES_IPS = @('185.199.108.153','185.199.109.153','185.199.110.153','185.199.111.153')
$VPS_IP = '178.104.2.252'

$current = Invoke-RestMethod "$base" -Headers $headers
$apex = $current.rrsets | Where-Object { $_.name -eq '@' -and $_.type -eq 'A' }
$www  = $current.rrsets | Where-Object { $_.name -eq 'www' }
Write-Output "current: @ A -> $(($apex.records.value) -join ', ') | www $($www.type) -> $(($www.records.value) -join ', ')"

if ($Revert) {
  $ops = @(
    @{ desc = "@ A -> $VPS_IP (ttl 3600)"; run = {
        Invoke-RestMethod -Method Post -Uri "$base/@/A/actions/set_records" -Headers $headers -Body (@{records=@(@{value=$VPS_IP})} | ConvertTo-Json) | Out-Null
        Invoke-RestMethod -Method Post -Uri "$base/@/A/actions/change_ttl" -Headers $headers -Body (@{ttl=3600} | ConvertTo-Json) | Out-Null } }
    @{ desc = "delete www $($www.type)"; run = {
        Invoke-RestMethod -Method Delete -Uri "$base/www/$($www.type)" -Headers $headers | Out-Null } }
    @{ desc = "www A -> $VPS_IP (ttl 3600)"; run = {
        Invoke-RestMethod -Method Post -Uri "$base" -Headers $headers -Body (@{name='www';type='A';ttl=3600;records=@(@{value=$VPS_IP})} | ConvertTo-Json) | Out-Null } }
  )
} else {
  $ops = @(
    @{ desc = "@ A -> GitHub Pages 4x IP (ttl 300)"; run = {
        Invoke-RestMethod -Method Post -Uri "$base/@/A/actions/set_records" -Headers $headers -Body (@{records=($GITHUB_PAGES_IPS | ForEach-Object {@{value=$_}})} | ConvertTo-Json) | Out-Null
        Invoke-RestMethod -Method Post -Uri "$base/@/A/actions/change_ttl" -Headers $headers -Body (@{ttl=300} | ConvertTo-Json) | Out-Null } }
    @{ desc = "delete www $($www.type)"; run = {
        Invoke-RestMethod -Method Delete -Uri "$base/www/$($www.type)" -Headers $headers | Out-Null } }
    @{ desc = "www CNAME -> ralle76.github.io (ttl 300)"; run = {
        Invoke-RestMethod -Method Post -Uri "$base" -Headers $headers -Body (@{name='www';type='CNAME';ttl=300;records=@(@{value='ralle76.github.io.'})} | ConvertTo-Json) | Out-Null } }
  )
}

$ops | ForEach-Object { Write-Output "  - $($_.desc)" }
if ($WhatIf) { Write-Output "WhatIf — no changes applied."; exit 0 }
$ops | ForEach-Object { & $_.run; Write-Output "done: $($_.desc)" }
Write-Output "DNS switch applied. MX/TXT/subdomains untouched."
