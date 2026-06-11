# Full fix: reset dashboard password, deploy Worker + Pages (Windows ARM — no wrangler needed)
# Usage:
#   $env:CLOUDFLARE_API_TOKEN = "your_token"
#   .\fix-all.ps1

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$AccountId = "0f61b15e3b7ef041399aed19c79e6e7e"
$ScriptName = "soft-violet-b153"
$ProjectName = "toledo-swift-haul-app"
$DashboardPassword = "ToledoSwift2026"

$Token = $env:CLOUDFLARE_API_TOKEN
if (-not $Token) {
  Write-Host "Missing CLOUDFLARE_API_TOKEN." -ForegroundColor Red
  Write-Host "Create at: https://dash.cloudflare.com/profile/api-tokens" -ForegroundColor Yellow
  Write-Host 'Then: $env:CLOUDFLARE_API_TOKEN = "paste_token"' -ForegroundColor Yellow
  exit 1
}

$Headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }

function Invoke-Cf {
  param([string]$Method, [string]$Uri, [object]$Body = $null)
  $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers }
  if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
  $r = Invoke-RestMethod @p
  if (-not $r.success) { throw ($r.errors | ConvertTo-Json -Compress) }
  return $r.result
}

Write-Host "Verifying API token..." -ForegroundColor Cyan
try {
  $verify = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" -Headers @{ Authorization = "Bearer $Token" }
  if (-not $verify.success) { throw "Token invalid" }
} catch {
  Write-Host "Cloudflare API token is invalid or expired. Create a new one and try again." -ForegroundColor Red
  exit 1
}

Write-Host "Setting DASHBOARD_PASSWORD to $DashboardPassword ..." -ForegroundColor Cyan
try {
  Invoke-Cf PUT "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$ScriptName/secrets" @{
    name  = "DASHBOARD_PASSWORD"
    text  = $DashboardPassword
    type  = "secret_text"
  } | Out-Null
} catch {
  Write-Host "Secret update note: $_" -ForegroundColor Yellow
}

Write-Host "Fetching Worker bindings..." -ForegroundColor Cyan
$settings = Invoke-Cf GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$ScriptName/settings"
$uploadBindings = @($settings.bindings | Where-Object { $_.type -ne "secret_text" } | ForEach-Object {
  if ($_.type -eq "d1") { @{ type = "d1"; name = $_.name; id = $_.id } }
  elseif ($_.type -eq "plain_text") { @{ type = "plain_text"; name = $_.name; text = $_.text } }
})

$workerCode = Get-Content "$Root\worker\index.js" -Raw
$metadata = @{ main_module = "index.js"; bindings = $uploadBindings } | ConvertTo-Json -Depth 6 -Compress

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

Write-Host "Deploying dashboard to Cloudflare Pages..." -ForegroundColor Cyan
function Get-FileHashB64([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return [Convert]::ToBase64String($sha)
}

$files = @(
  "$Root\dashboard\index.html",
  "$Root\dashboard\styles.css",
  "$Root\dashboard\app.js"
)
$manifest = @{}
$fileMap = @{}
foreach ($f in $files) {
  $name = "/" + (Split-Path $f -Leaf)
  $hash = Get-FileHashB64 $f
  $manifest[$name] = $hash
  $fileMap[$hash] = $f
}
$manifestJson = $manifest | ConvertTo-Json -Compress

$boundary2 = [System.Guid]::NewGuid().ToString()
$utf8 = [System.Text.Encoding]::UTF8
$multipart = New-Object System.Collections.Generic.List[byte]
$manifestPart = "--$boundary2$LF" + "Content-Disposition: form-data; name=`"manifest`"$LF" + "Content-Type: application/json$LF$LF" + $manifestJson + "$LF"
$multipart.AddRange($utf8.GetBytes($manifestPart))

foreach ($hash in $fileMap.Keys) {
  $path = $fileMap[$hash]
  $fileName = Split-Path $path -Leaf
  $fileBytes = [System.IO.File]::ReadAllBytes($path)
  $header = "--$boundary2$LF" + "Content-Disposition: form-data; name=`"$hash`"; filename=`"$fileName`"$LF" + "Content-Type: application/octet-stream$LF$LF"
  $multipart.AddRange($utf8.GetBytes($header))
  $multipart.AddRange($fileBytes)
  $multipart.AddRange($utf8.GetBytes("$LF"))
}
$multipart.AddRange($utf8.GetBytes("--$boundary2--$LF"))

Invoke-RestMethod -Method POST `
  -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$ProjectName/deployments" `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType "multipart/form-data; boundary=$boundary2" `
  -Body ([byte[]]$multipart.ToArray()) | Out-Null

Write-Host "Testing API login..." -ForegroundColor Cyan
Start-Sleep -Seconds 2
$test = Invoke-RestMethod -Uri "https://api.toledoswifthaul.com/api/stats" -Headers @{ Authorization = "Bearer $DashboardPassword" }
Write-Host "API stats OK: today=$($test.today) total=$($test.total)" -ForegroundColor Green

$creds = @{
  apiUrl            = "https://api.toledoswifthaul.com"
  dashboardUrl      = "https://toledo-swift-haul-app.pages.dev"
  dashboardAltUrl   = "https://app.toledoswifthaul.com"
  dashboardPassword = $DashboardPassword
} | ConvertTo-Json
$creds | Set-Content "$Root\deploy-output.json" -Encoding UTF8

Write-Host ""
Write-Host "=== ALL FIXED ===" -ForegroundColor Green
Write-Host "Dashboard: https://toledo-swift-haul-app.pages.dev"
Write-Host "API URL:   https://api.toledoswifthaul.com"
Write-Host "Password:  $DashboardPassword"
Write-Host ""
Write-Host "Hard refresh (Ctrl+Shift+R), then log in."
