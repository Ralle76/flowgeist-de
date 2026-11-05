# Property of Ralf Carsjens - flowgeist-de - ISO 27001 Compliant
# enable-https.ps1 — check GitHub Pages cert status for flowgeist.de and
# enforce HTTPS once the certificate is issued. Safe to re-run anytime.
# Usage: ./enable-https.ps1          (check + enforce when ready)
#        ./enable-https.ps1 -Watch   (poll every 10 min until done)

param([switch]$Watch)

function Get-CertState {
  gh api repos/Ralle76/flowgeist-de/pages --jq ".https_certificate.state" 2>$null
}

function Test-Https {
  $code = curl.exe -s -o NUL -w "%{http_code}" --resolve "flowgeist.de:443:185.199.108.153" --max-time 8 https://flowgeist.de/
  return $code -eq "200"
}

do {
  $state = Get-CertState
  $https = Test-Https
  Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm') cert=$state https=$https"

  if ($https) {
    Write-Output "Certificate live — enabling HTTPS enforcement..."
    gh api repos/Ralle76/flowgeist-de/pages -X PUT -f https_enforced=true --jq "{https_enforced: .https_enforced}"
    Write-Output "Done. http://flowgeist.de now redirects to https."
    break
  }

  if (-not $Watch) {
    Write-Output "Not ready yet. Re-run later, or with -Watch to poll."
    break
  }
  Start-Sleep 600
} while ($true)
