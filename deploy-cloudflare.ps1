# Deploy Toledo Swift Haul dashboard to Cloudflare (API — works on Windows ARM)
# Usage:
#   $env:CLOUDFLARE_API_TOKEN = "your_token"
#   .\deploy-cloudflare.ps1

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Token = $env:CLOUDFLARE_API_TOKEN
if (-not $Token) {
  Write-Host "Missing CLOUDFLARE_API_TOKEN environment variable." -ForegroundColor Red
  Write-Host "Create one at: https://dash.cloudflare.com/profile/api-tokens" -ForegroundColor Yellow
  Write-Host 'Then run: $env:CLOUDFLARE_API_TOKEN = "paste_token_here"' -ForegroundColor Yellow
  exit 1
}

$Headers = @{
  Authorization = "Bearer $Token"
  "Content-Type" = "application/json"
}

function Invoke-CfApi {
  param([string]$Method, [string]$Uri, [object]$Body = $null)
  $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers }
  if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
  $res = Invoke-RestMethod @params
  if (-not $res.success) { throw "Cloudflare API error: $($res.errors | ConvertTo-Json -Compress)" }
  return $res.result
}

Write-Host "Fetching Cloudflare account..." -ForegroundColor Cyan
$accounts = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/accounts"
$account = $accounts | Select-Object -First 1
$AccountId = $account.id
Write-Host "Account: $($account.name) ($AccountId)"

Write-Host "Fetching zone..." -ForegroundColor Cyan
$zones = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/zones?name=toledoswifthaul.com"
$zone = $zones | Select-Object -First 1
if (-not $zone) { throw "Zone toledoswifthaul.com not found in Cloudflare." }
$ZoneId = $zone.id

# D1 database
Write-Host "Creating D1 database (skip if exists)..." -ForegroundColor Cyan
$dbId = $null
try {
  $dbs = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/d1/database"
  $existing = $dbs | Where-Object { $_.name -eq "toledo-swift-haul-calls" } | Select-Object -First 1
  if ($existing) {
    $dbId = $existing.uuid
    Write-Host "Using existing D1: $dbId"
  } else {
    $created = Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/d1/database" @{ name = "toledo-swift-haul-calls" }
    $dbId = $created.uuid
    Write-Host "Created D1: $dbId"
  }
} catch {
  throw "D1 setup failed: $_"
}

$schema = Get-Content "$Root\schema.sql" -Raw
$sqlStatements = ($schema -split ";" | ForEach-Object { $_.Trim() }) | Where-Object { $_ }
foreach ($sql in $sqlStatements) {
  Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/d1/database/$dbId/query" @{ sql = $sql } | Out-Null
}
Write-Host "D1 schema applied."

# Dashboard password
$DashboardPassword = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
Write-Host "Generated dashboard password (save this): $DashboardPassword" -ForegroundColor Green

# Deploy Worker via multipart API
Write-Host "Deploying Worker..." -ForegroundColor Cyan
$workerPath = "$Root\worker\index.js"
$workerCode = Get-Content $workerPath -Raw
$metadata = @{
  main_module = "index.js"
  bindings = @(
    @{ type = "d1"; name = "DB"; id = $dbId }
    @{ type = "plain_text"; name = "DASHBOARD_PASSWORD"; text = $DashboardPassword }
  )
} | ConvertTo-Json -Depth 5 -Compress

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

$uploadHeaders = @{ Authorization = "Bearer $Token" }
Invoke-RestMethod -Method PUT `
  -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/toledo-swift-haul-api" `
  -Headers $uploadHeaders `
  -ContentType "multipart/form-data; boundary=$boundary" `
  -Body $bodyBytes | Out-Null

# Enable workers.dev subdomain
try {
  Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/toledo-swift-haul-api/subdomain" @{ enabled = $true } | Out-Null
} catch { }

$subdomain = (Invoke-CfApi GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/subdomain").subdomain
$WorkerDevUrl = "https://toledo-swift-haul-api.$subdomain.workers.dev"
Write-Host "Worker URL: $WorkerDevUrl"

# Custom domain api.toledoswifthaul.com
try {
  Invoke-CfApi PUT "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/toledo-swift-haul-api/script-settings" @{
    logpush = $false
  } | Out-Null
  Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/domains" @{
    hostname = "api.toledoswifthaul.com"
    service = "toledo-swift-haul-api"
    environment = "production"
  } | Out-Null
  Write-Host "Custom domain: https://api.toledoswifthaul.com"
} catch {
  Write-Host "Custom domain may need manual add in Workers settings: $_" -ForegroundColor Yellow
}

# Pages project + deploy dashboard
Write-Host "Deploying dashboard to Pages..." -ForegroundColor Cyan
$projectName = "toledo-swift-haul-app"
try {
  Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects" @{
    name = $projectName
    production_branch = "main"
  } | Out-Null
} catch { }

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
$sb = New-Object System.Text.StringBuilder
function Add-Part([string]$headers, [byte[]]$content) {
  [void]$sb.Append("--$boundary2$LF")
  [void]$sb.Append($headers)
  [void]$sb.Append($LF)
  $script:partBytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString()) + $content + [System.Text.Encoding]::UTF8.GetBytes("$LF")
}

$multipart = New-Object System.Collections.Generic.List[byte]
$utf8 = [System.Text.Encoding]::UTF8

# manifest part
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
  -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$projectName/deployments" `
  -Headers @{ Authorization = "Bearer $Token" } `
  -ContentType "multipart/form-data; boundary=$boundary2" `
  -Body ([byte[]]$multipart.ToArray()) | Out-Null

$pagesUrl = "https://$projectName.pages.dev"
Write-Host "Pages URL: $pagesUrl"

try {
  Invoke-CfApi POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$projectName/domains" @{
    name = "app.toledoswifthaul.com"
  } | Out-Null
  Write-Host "Dashboard domain: https://app.toledoswifthaul.com"
} catch {
  Write-Host "Add app.toledoswifthaul.com in Pages custom domains if needed." -ForegroundColor Yellow
}

# Save credentials locally
$creds = @{
  apiUrl = "https://api.toledoswifthaul.com"
  workerDevUrl = $WorkerDevUrl
  dashboardUrl = "https://app.toledoswifthaul.com"
  dashboardPassword = $DashboardPassword
  twilioVoiceWebhook = "https://api.toledoswifthaul.com/voice"
  twilioStatusWebhook = "https://api.toledoswifthaul.com/voice/status"
} | ConvertTo-Json
$creds | Set-Content "$Root\deploy-output.json" -Encoding UTF8

Write-Host ""
Write-Host "=== DEPLOY COMPLETE ===" -ForegroundColor Green
Write-Host "Dashboard: https://app.toledoswifthaul.com"
Write-Host "API:       https://api.toledoswifthaul.com"
Write-Host "Password:  $DashboardPassword"
Write-Host ""
Write-Host "Twilio -> (567) 777-3443 -> Voice webhook:"
Write-Host "  https://api.toledoswifthaul.com/voice"
Write-Host "Call status:"
Write-Host "  https://api.toledoswifthaul.com/voice/status"
Write-Host ""
Write-Host "Saved to deploy-output.json"
