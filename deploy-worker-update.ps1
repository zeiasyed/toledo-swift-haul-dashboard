# Update soft-violet-b153 Worker (CORS fix) via Cloudflare API
# Run in Cursor terminal:
#   $env:CLOUDFLARE_API_TOKEN = "paste_your_token"
#   .\deploy-worker-update.ps1

$ErrorActionPreference = "Stop"
$Token = $env:CLOUDFLARE_API_TOKEN
if (-not $Token) {
  Write-Host "Paste your Cloudflare API token, then press Enter:" -ForegroundColor Yellow
  $Token = Read-Host -AsSecureString
  $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
  )
}

$AccountId = "0f61b15e3b7ef041399aed19c79e6e7e"
$ScriptName = "soft-violet-b153"
$Root = $PSScriptRoot
$Headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }

function Invoke-Cf($Method, $Uri, $Body = $null) {
  $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers }
  if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
  $r = Invoke-RestMethod @p
  if (-not $r.success) { throw ($r.errors | ConvertTo-Json -Compress) }
  return $r.result
}

Write-Host "Fetching current Worker bindings..." -ForegroundColor Cyan
$settings = Invoke-Cf GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$ScriptName/settings"
$bindings = @($settings.bindings | ForEach-Object {
  if ($_.type -eq "d1") {
    @{ type = "d1"; name = $_.name; id = $_.id }
  } elseif ($_.type -eq "secret_text") {
    @{ type = "secret_text"; name = $_.name; text = "" }
  } elseif ($_.type -eq "plain_text") {
    @{ type = "plain_text"; name = $_.name; text = $_.text }
  } else {
    $_
  }
})

# secret_text bindings must omit text on upload — filter to d1 + plain_text only
$uploadBindings = @($settings.bindings | Where-Object { $_.type -ne "secret_text" } | ForEach-Object {
  if ($_.type -eq "d1") { @{ type = "d1"; name = $_.name; id = $_.id } }
  elseif ($_.type -eq "plain_text") { @{ type = "plain_text"; name = $_.name; text = $_.text } }
})

$workerCode = Get-Content "$Root\worker\index.js" -Raw
$metadata = @{
  main_module = "index.js"
  bindings = $uploadBindings
} | ConvertTo-Json -Depth 6 -Compress

$boundary = [System.Guid]::NewGuid().ToString()
$LF = "`r`n"
$bodyLines = @(
  "--$boundary",
  "Content-Disposition: form-data; name=`"metadata`"",
  "Content-Type: application/json",
  "",
  $metadata,
  "--$boundary",
  "Content-Disposition: form-data; name=`"index.js`"; filename=`"index.js`"",
  "Content-Type: application/javascript+module",
  "",
  $workerCode,
  "--$boundary--"
)
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join $LF))

Write-Host "Deploying Worker $ScriptName..." -ForegroundColor Cyan
Invoke-RestMethod -Method PUT `
  -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$ScriptName" `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType "multipart/form-data; boundary=$boundary" `
  -Body $bodyBytes | Out-Null

Write-Host ""
Write-Host "Deployed! Test:" -ForegroundColor Green
Write-Host "  https://api.toledoswifthaul.com/health"
Write-Host ""
Write-Host "Then refresh dashboard and click View Dashboard."
