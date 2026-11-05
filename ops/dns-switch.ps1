# Property of Ralf Carsjens - flowgeist-de - ISO 27001 Compliant
# dns-switch.ps1 — Point flowgeist.de (+www) at GitHub Pages via Hetzner DNS API.
# Reads token from $env:HETZNER_DNS_TOKEN (loaded from global_secrets.env).
# Usage: ./dns-switch.ps1 [-WhatIf] [-Revert]
#   -WhatIf : dry-run, prints planned changes only
#   -Revert : restore A records to the Hetzner VPS (178.104.2.252)

param(
  [switch]$WhatIf,
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'

if (-not $env:HETZNER_DNS_TOKEN) {
  Get-Content "$env:USERPROFILE\CascadeProjects\global_secrets.env" | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim('"').Trim("'"))
    }
  }
}
if (-not $env:HETZNER_DNS_TOKEN) { throw "HETZNER_DNS_TOKEN not set (create at https://dns.hetzner.com)" }

$headers = @{ 'Auth-API-Token' = $env:HETZNER_DNS_TOKEN }
$base = 'https://dns.hetzner.com/api/v1'

$GITHUB_PAGES_IPS = @('185.199.108.153','185.199.109.153','185.199.110.153','185.199.111.153')
$VPS_IP = '178.104.2.252'

# --- locate zone ---
$zones = Invoke-RestMethod -Uri "$base/zones" -Headers $headers
$zone = $zones.zones | Where-Object { $_.name -eq 'flowgeist.de' }
if (-not $zone) { throw "Zone flowgeist.de not found in this Hetzner DNS account" }
Write-Output "Zone: $($zone.name) (id $($zone.id))"

# --- fetch records ---
$all = @()
$page = 1
do {
  $r = Invoke-RestMethod -Uri "$base/records?zone_id=$($zone.id)&per_page=100&page=$page" -Headers $headers
  $all += $r.records
  $page++
} while ($r.records.Count -eq 100)

$apex = $all | Where-Object { $_.type -eq 'A' -and $_.name -eq '@' }
$www  = $all | Where-Object { $_.type -in @('A','CNAME') -and $_.name -eq 'www' }

Write-Output "Current apex A: $($apex | ForEach-Object { "$($_.value) (id $($_.id), ttl $($_.ttl))" })"
Write-Output "Current www   : $($www  | ForEach-Object { "$($_.type) $($_.value) (id $($_.id))" })"

$plan = @()

if ($Revert) {
  foreach ($rec in $apex) { $plan += @{ action = 'delete'; id = $rec.id; desc = "delete A @ $($rec.value)" } }
  $plan += @{ action = 'create'; body = @{ zone_id = $zone.id; type = 'A'; name = '@'; value = $VPS_IP; ttl = 3600 }; desc = "create A @ $VPS_IP" }
  foreach ($rec in $www) { $plan += @{ action = 'delete'; id = $rec.id; desc = "delete $($rec.type) www $($rec.value)" } }
  $plan += @{ action = 'create'; body = @{ zone_id = $zone.id; type = 'A'; name = 'www'; value = $VPS_IP; ttl = 3600 }; desc = "create A www $VPS_IP" }
} else {
  foreach ($rec in $apex) { $plan += @{ action = 'delete'; id = $rec.id; desc = "delete A @ $($rec.value)" } }
  foreach ($ip in $GITHUB_PAGES_IPS) {
    $plan += @{ action = 'create'; body = @{ zone_id = $zone.id; type = 'A'; name = '@'; value = $ip; ttl = 300 }; desc = "create A @ $ip" }
  }
  foreach ($rec in $www) { $plan += @{ action = 'delete'; id = $rec.id; desc = "delete $($rec.type) www $($rec.value)" } }
  $plan += @{ action = 'create'; body = @{ zone_id = $zone.id; type = 'CNAME'; name = 'www'; value = 'ralle76.github.io'; ttl = 300 }; desc = 'create CNAME www ralle76.github.io' }
}

Write-Output "`nPlanned changes:"
$plan | ForEach-Object { Write-Output "  - $($_.desc)" }

if ($WhatIf) { Write-Output "`nWhatIf — no changes applied."; exit 0 }

foreach $step in $plan {
  if ($step.action -eq 'delete') {
    Invoke-RestMethod -Uri "$base/records/$($step.id)" -Method Delete -Headers $headers | Out-Null
  } else {
    Invoke-RestMethod -Uri "$base/records" -Method Post -Headers $headers -Body ($step.body | ConvertTo-Json) -ContentType 'application/json' | Out-Null
  }
  Write-Output "done: $($step.desc)"
}

Write-Output "`nDNS switch applied. MX/TXT/subdomain records untouched."
