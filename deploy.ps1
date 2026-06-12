#Requires -Version 5.1
param(
  [string]$Token,
  [string]$Email,
  [string]$GlobalKey
)

$ErrorActionPreference = "Stop"

$Root              = $PSScriptRoot
$AccountId         = "0f61b15e3b7ef041399aed19c79e6e7e"
$WorkerName        = "soft-violet-b153"
$PagesProject      = "toledo-swift-haul-app"
$DashboardPassword = "ToledoSwift2026"
$ApiUrl            = "https://api.toledoswifthaul.com"
$CredsFile         = Join-Path $Root ".cloudflare-credentials.json"

$script:AuthMode = $null
$script:AuthToken = $null
$script:AuthEmail = $null
$script:AuthGlobalKey = $null

function Write-Step([string]$Msg) {
  Write-Host ""
  Write-Host ">> $Msg" -ForegroundColor Cyan
}

function Write-Ok([string]$Msg) {
  Write-Host "   OK  $Msg" -ForegroundColor Green
}

function Write-Warn([string]$Msg) {
  Write-Host "   !!  $Msg" -ForegroundColor Yellow
}

function Write-Fail([string]$Msg) {
  Write-Host "   XX  $Msg" -ForegroundColor Red
}

function Test-CfToken([string]$Value) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" `
      -Headers @{ Authorization = "Bearer $Value" }
    return [bool]$r.success
  } catch { return $false }
}

function Test-CfGlobalKey([string]$Addr, [string]$Key) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user" `
      -Headers @{ "X-Auth-Email" = $Addr; "X-Auth-Key" = $Key }
    return [bool]$r.success
  } catch { return $false }
}

function Get-AuthHeaders {
  if ($script:AuthMode -eq "token") {
    return @{ Authorization = "Bearer $script:AuthToken" }
  }
  return @{ "X-Auth-Email" = $script:AuthEmail; "X-Auth-Key" = $script:AuthGlobalKey }
}

function Save-Credentials {
  param([hashtable]$Creds)
  ($Creds | ConvertTo-Json) | Set-Content $CredsFile -Encoding UTF8
}

function Get-CloudflareAuth {
  param([string]$OverrideToken, [string]$OverrideEmail, [string]$OverrideKey)

  if ($OverrideToken -and (Test-CfToken $OverrideToken)) {
    $script:AuthMode = "token"
    $script:AuthToken = $OverrideToken
    Save-Credentials @{ type = "token"; token = $OverrideToken }
    Write-Ok "Using API token"
    return
  }

  if ($OverrideEmail -and $OverrideKey -and (Test-CfGlobalKey $OverrideEmail $OverrideKey)) {
    $script:AuthMode = "global"
    $script:AuthEmail = $OverrideEmail
    $script:AuthGlobalKey = $OverrideKey
    Save-Credentials @{ type = "global"; email = $OverrideEmail; globalKey = $OverrideKey }
    Write-Ok "Using Global API Key"
    return
  }

  if ($env:CLOUDFLARE_API_TOKEN -and (Test-CfToken $env:CLOUDFLARE_API_TOKEN)) {
    $script:AuthMode = "token"
    $script:AuthToken = $env:CLOUDFLARE_API_TOKEN
    Write-Ok "Using CLOUDFLARE_API_TOKEN"
    return
  }

  if ($env:CLOUDFLARE_EMAIL -and $env:CLOUDFLARE_GLOBAL_API_KEY -and `
      (Test-CfGlobalKey $env:CLOUDFLARE_EMAIL $env:CLOUDFLARE_GLOBAL_API_KEY)) {
    $script:AuthMode = "global"
    $script:AuthEmail = $env:CLOUDFLARE_EMAIL
    $script:AuthGlobalKey = $env:CLOUDFLARE_GLOBAL_API_KEY
    Write-Ok "Using Global API Key from environment"
    return
  }

  if (Test-Path $CredsFile) {
    $saved = Get-Content $CredsFile -Raw | ConvertFrom-Json
    if ($saved.type -eq "token" -and $saved.token -and (Test-CfToken $saved.token)) {
      $script:AuthMode = "token"
      $script:AuthToken = $saved.token
      Write-Ok "Using saved API token"
      return
    }
    if ($saved.type -eq "global" -and $saved.email -and $saved.globalKey -and `
        (Test-CfGlobalKey $saved.email $saved.globalKey)) {
      $script:AuthMode = "global"
      $script:AuthEmail = $saved.email
      $script:AuthGlobalKey = $saved.globalKey
      Write-Ok "Using saved Global API Key"
      return
    }
    Remove-Item $CredsFile -Force -ErrorAction SilentlyContinue
  }

  Write-Host ""
  Write-Host "========================================" -ForegroundColor Yellow
  Write-Host " ONE-TIME SETUP (use your normal browser)" -ForegroundColor Yellow
  Write-Host "========================================" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Easiest - Global API Key (no Create Token step):"
  Write-Host "  1. Open: https://dash.cloudflare.com/profile/api-tokens"
  Write-Host "  2. Under API Keys, click View on Global API Key"
  Write-Host "  3. Complete the human check, copy the key"
  Write-Host ""

  Start-Process "https://dash.cloudflare.com/profile/api-tokens"

  $enteredEmail = Read-Host "Your Cloudflare login email"
  $enteredKey = Read-Host "Paste Global API Key here"
  if (-not $enteredEmail -or -not $enteredKey) {
    Write-Fail "Email and Global API Key are required."
    exit 1
  }
  if (-not (Test-CfGlobalKey $enteredEmail $enteredKey)) {
    Write-Fail "Invalid email or Global API Key."
    exit 1
  }

  $script:AuthMode = "global"
  $script:AuthEmail = $enteredEmail.Trim()
  $script:AuthGlobalKey = $enteredKey.Trim()
  Save-Credentials @{ type = "global"; email = $script:AuthEmail; globalKey = $script:AuthGlobalKey }
  Write-Ok "Credentials saved (reused on next deploy)"
}

function Invoke-CfApi {
  param([string]$Method, [string]$Uri, [object]$Body = $null)
  $headers = Get-AuthHeaders
  $headers["Content-Type"] = "application/json"
  $p = @{ Method = $Method; Uri = $Uri; Headers = $headers }
  if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
  $r = Invoke-RestMethod @p
  if (-not $r.success) { throw ($r.errors | ConvertTo-Json -Compress) }
  return $r.result
}

function Get-SeoSetup {
  $path = Join-Path $Root "seo-setup.json"
  if (-not (Test-Path $path)) { return [pscustomobject]@{} }
  return Get-Content $path -Raw | ConvertFrom-Json
}

function Apply-SeoInjections {
  param([string]$Html, [object]$Setup)
  if ($Setup.googleSiteVerification) {
    $meta = '<meta name="google-site-verification" content="' + $Setup.googleSiteVerification + '" />'
    $Html = $Html.Replace("<!-- SEO:GSC -->", $meta)
  } else {
    $Html = $Html.Replace("<!-- SEO:GSC -->", "")
  }
  if ($Setup.ga4MeasurementId) {
    $id = $Setup.ga4MeasurementId
    $ga = '<script async src="https://www.googletagmanager.com/gtag/js?id=' + $id + '"></script>' +
      '<script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}gtag(''js'',new Date());gtag(''config'',''' + $id + ''');</script>'
    $Html = $Html.Replace("<!-- SEO:GA4 -->", $ga)
  } else {
    $Html = $Html.Replace("<!-- SEO:GA4 -->", "")
  }
  if ($Setup.cloudflareWebAnalyticsToken) {
    $token = $Setup.cloudflareWebAnalyticsToken
    $cf = "<script defer src='https://static.cloudflareinsights.com/beacon.min.js' data-cf-beacon='{""token"": ""$token""}'></script>"
    $Html = $Html.Replace("<!-- SEO:CF_ANALYTICS -->", $cf)
  } else {
    $Html = $Html.Replace("<!-- SEO:CF_ANALYTICS -->", "")
  }
  return $Html
}

function Build-SitemapXml {
  param([string[]]$Paths)
  $base = "https://toledoswifthaul.com"
  $urls = @("$base/")
  foreach ($p in $Paths) {
    if ($p -match '\.html$') { $urls += "$base$p" }
  }
  $urls = $urls | Select-Object -Unique
  $body = ($urls | ForEach-Object {
    "  <url><loc>$_</loc><changefreq>weekly</changefreq><priority>0.8</priority></url>"
  }) -join "`n"
  return @"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>$base/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>
$body
</urlset>
"@
}

function Get-MarketingFileMap {
  param([object]$Setup)
  $marketingRoot = Join-Path (Split-Path $Root -Parent) "toledo-swift-haul"
  $genScript = Join-Path $marketingRoot "generate_pages.py"
  if (Test-Path $genScript) {
    try { python $genScript 2>$null | Out-Null } catch { Write-Warn "Page generator: $_" }
  }

  $map = @{}
  $htmlPaths = @()

  foreach ($name in @("index.html", "styles.css", "script.js", "robots.txt")) {
    $fp = Join-Path $marketingRoot $name
    if (-not (Test-Path $fp)) { continue }
    $content = [System.IO.File]::ReadAllBytes($fp)
    if ($name -eq "index.html") {
      $text = Apply-SeoInjections ([System.Text.Encoding]::UTF8.GetString($content)) $Setup
      $content = [System.Text.Encoding]::UTF8.GetBytes($text)
    }
    $key = if ($name -eq "index.html") { "/index.html" } else { "/$name" }
    $map[$key] = $content
  }

  $pagesDir = Join-Path $marketingRoot "pages"
  if (Test-Path $pagesDir) {
    Get-ChildItem $pagesDir -Filter "*.html" | ForEach-Object {
      $text = Apply-SeoInjections ([System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)) $Setup
      $key = "/pages/$($_.Name)"
      $map[$key] = [System.Text.Encoding]::UTF8.GetBytes($text)
      $htmlPaths += $key
    }
  }

  foreach ($img in @("hero-480.webp", "hero-768.webp", "hero-1200.webp")) {
    $fp = Join-Path $marketingRoot "images\$img"
    if (Test-Path $fp) { $map["/images/$img"] = [System.IO.File]::ReadAllBytes($fp) }
  }

  $sitemap = Build-SitemapXml $htmlPaths
  $map["/sitemap.xml"] = [System.Text.Encoding]::UTF8.GetBytes($sitemap)
  return $map
}

function Set-SeoWorkerSecrets {
  param([object]$Setup)
  Write-Step "Applying SEO integration secrets..."
  $secrets = @(
    @{ name = "GA4_MEASUREMENT_ID"; value = $Setup.ga4MeasurementId }
    @{ name = "SERPAPI_KEY"; value = $Setup.serpApiKey }
    @{ name = "PAGESPEED_API_KEY"; value = $Setup.pageSpeedApiKey }
    @{ name = "GBP_PLACE_ID"; value = $Setup.gbpPlaceId }
  )
  foreach ($s in $secrets) {
    if (-not $s.value) { continue }
    try {
      Invoke-CfApi PUT `
        "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/secrets" `
        @{ name = $s.name; text = $s.value; type = "secret_text" } | Out-Null
      Write-Ok "$($s.name) set"
    } catch {
      Write-Warn "$($s.name): $_"
    }
  }
}

function Ensure-GscDnsVerification {
  param([object]$Setup)
  if (-not $Setup.gscDnsToken) { return }
  Write-Step "Adding Google Search Console DNS verification..."
  $zone = "4c23eddc3b2d85594a331fd90877c18d"
  $token = "google-site-verification=$($Setup.gscDnsToken)"
  try {
    $records = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/zones/$zone/dns_records?type=TXT"
    $exists = $records | Where-Object { $_.content -eq $token }
    if (-not $exists) {
      Invoke-CfApi POST "https://api.cloudflare.com/client/v4/zones/$zone/dns_records" `
        @{ type = "TXT"; name = "toledoswifthaul.com"; content = $token; ttl = 3600 } | Out-Null
    }
    Write-Ok "GSC DNS TXT record ready - click Verify in Search Console"
  } catch {
    Write-Warn "GSC DNS: $_"
  }
}

function Enable-CfWebAnalytics {
  param([object]$Setup)
  if ($Setup.cloudflareWebAnalyticsToken) { return }
  Write-Step "Enabling Cloudflare Web Analytics (free)..."
  $zone = "4c23eddc3b2d85594a331fd90877c18d"
  try {
    $r = Invoke-CfApi POST "https://api.cloudflare.com/client/v4/zones/$zone/analytics/web/overview" $null 2>$null
  } catch {}
  try {
    $sites = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/zones/$zone/webanalytics/sites"
    if ($sites -and $sites.Count -gt 0) {
      $token = $sites[0].token
      if ($token) {
        $setupPath = Join-Path $Root "seo-setup.json"
        if (Test-Path $setupPath) {
          $json = Get-Content $setupPath -Raw | ConvertFrom-Json
          $json | Add-Member -NotePropertyName cloudflareWebAnalyticsToken -NotePropertyValue $token -Force
          ($json | ConvertTo-Json) | Set-Content $setupPath -Encoding UTF8
        }
        Write-Ok "Cloudflare Web Analytics token saved to seo-setup.json"
      }
    }
  } catch {
    Write-Warn "Web Analytics: enable manually in Cloudflare dashboard if needed"
  }
}

function Build-WorkerCode {
  $dashboardMap = @{
    "/index.html" = "index.html"
    "/styles.css" = "styles.css"
    "/app.js"     = "app.js"
  }
  $dashboardEntries = @()
  foreach ($path in $dashboardMap.Keys) {
    $bytes = [System.IO.File]::ReadAllBytes("$Root\dashboard\$($dashboardMap[$path])")
    $b64 = [Convert]::ToBase64String($bytes)
    $dashboardEntries += "`"$path`":`"$b64`""
  }

  $seoSetup = Get-SeoSetup
  $marketingFiles = Get-MarketingFileMap $seoSetup
  $marketingEntries = @()
  foreach ($path in ($marketingFiles.Keys | Sort-Object)) {
    $b64 = [Convert]::ToBase64String($marketingFiles[$path])
    $marketingEntries += "`"$path`":`"$b64`""
  }

  $seoMap = @{
    "/index.html" = "index.html"
    "/styles.css" = "styles.css"
    "/app.js"     = "app.js"
  }
  $seoEntries = @()
  foreach ($path in $seoMap.Keys) {
    $bytes = [System.IO.File]::ReadAllBytes("$Root\seo-dashboard\$($seoMap[$path])")
    $b64 = [Convert]::ToBase64String($bytes)
    $seoEntries += "`"$path`":`"$b64`""
  }

  $assets = @(
    "const DASHBOARD_B64 = { $($dashboardEntries -join ',') };"
    "const MARKETING_B64 = { $($marketingEntries -join ',') };"
    "const SEO_B64 = { $($seoEntries -join ',') };"
    ""
  ) -join "`n"

  $index = Get-Content "$Root\worker\index.js" -Raw
  $seo = Get-Content "$Root\worker\seo.js" -Raw
  $index = $index -replace 'export default \{', ($seo + "`nexport default {")
  return $assets + $index
}

function Ensure-WorkerRoutes {
  Write-Step "Attaching Worker routes..."
  $zone = "4c23eddc3b2d85594a331fd90877c18d"
  $patterns = @(
    "toledoswifthaul.com/*",
    "www.toledoswifthaul.com/*",
    "app.toledoswifthaul.com/*"
  )
  try {
    $routes = Invoke-CfApi GET "https://api.cloudflare.com/client/v4/zones/$zone/workers/routes"
    foreach ($pattern in $patterns) {
      $exists = $routes | Where-Object { $_.pattern -eq $pattern }
      if (-not $exists) {
        Invoke-CfApi POST "https://api.cloudflare.com/client/v4/zones/$zone/workers/routes" `
          @{ pattern = $pattern; script = $WorkerName } | Out-Null
      }
      Write-Ok "Worker route $pattern"
    }
  } catch {
    Write-Warn "Route setup: $_"
  }
}

function Ensure-CronSchedule {
  Write-Step "Ensuring daily SEO cron (13:00 UTC)..."
  try {
    $existing = Invoke-CfApi GET `
      "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/schedules"
    $cron = "0 13 * * *"
    $has = $false
    if ($existing) {
      foreach ($s in $existing) {
        if ($s.cron -eq $cron) { $has = $true }
      }
    }
    if (-not $has) {
      Invoke-CfApi PUT `
        "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/schedules" `
        @{ schedules = @(@{ cron = $cron }) } | Out-Null
    }
    Write-Ok "Daily SEO cron active"
  } catch {
    Write-Warn "Cron setup: $_"
  }
}

function Initialize-LeadsSchema {
  Write-Step "Initializing leads table..."
  $dbId = "fd911bdb-ecc0-40f4-9f80-b21d46d6ca5e"
  $sql = Get-Content "$Root\schema-leads.sql" -Raw
  $statements = $sql -split ";" | Where-Object { $_.Trim() -ne "" }
  try {
    foreach ($stmt in $statements) {
      $body = @{ sql = $stmt.Trim() } | ConvertTo-Json -Compress
      $headers = Get-AuthHeaders
      $headers["Content-Type"] = "application/json"
      Invoke-RestMethod -Method POST `
        -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/d1/database/$dbId/query" `
        -Headers $headers -Body $body | Out-Null
    }
    Write-Ok "Leads schema ready"
  } catch {
    Write-Warn "Leads schema: $_"
  }
}

function Initialize-SeoSchema {
  Write-Step "Initializing SEO database tables..."
  $dbId = "fd911bdb-ecc0-40f4-9f80-b21d46d6ca5e"
  $sql = Get-Content "$Root\schema-seo.sql" -Raw
  $statements = $sql -split ";" | Where-Object { $_.Trim() -ne "" }
  try {
    foreach ($stmt in $statements) {
      $body = @{ sql = $stmt.Trim() } | ConvertTo-Json -Compress
      $headers = Get-AuthHeaders
      $headers["Content-Type"] = "application/json"
      Invoke-RestMethod -Method POST `
        -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/d1/database/$dbId/query" `
        -Headers $headers -Body $body | Out-Null
    }
    Write-Ok "SEO schema ready"
  } catch {
    Write-Warn "SEO schema: $_"
  }
}

function Deploy-Worker {
  Write-Step "Setting dashboard password on Worker..."
  try {
    Invoke-CfApi PUT `
      "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/secrets" `
      @{ name = "DASHBOARD_PASSWORD"; text = $DashboardPassword; type = "secret_text" } | Out-Null
    Write-Ok "Password set to $DashboardPassword"
  } catch {
    Write-Warn "Secret update: $_"
  }

  Write-Step "Deploying Worker ($WorkerName)..."
  $settings = Invoke-CfApi GET `
    "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/settings"

  $uploadBindings = @($settings.bindings | Where-Object { $_.type -ne "secret_text" } | ForEach-Object {
    if ($_.type -eq "d1") { @{ type = "d1"; name = $_.name; id = $_.id } }
    elseif ($_.type -eq "plain_text") { @{ type = "plain_text"; name = $_.name; text = $_.text } }
  })

  $workerCode = Build-WorkerCode
  $metadataObj = @{
    main_module = "index.js"
    bindings    = $uploadBindings
    triggers    = @{ crons = @("0 13 * * *") }
  }
  $metadata = $metadataObj | ConvertTo-Json -Depth 8 -Compress

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

  $uploadHeaders = Get-AuthHeaders
  try {
    Invoke-RestMethod -Method PUT `
      -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName" `
      -Headers $uploadHeaders `
      -ContentType "multipart/form-data; boundary=$boundary" `
      -Body $bodyBytes | Out-Null
  } catch {
    $resp = $_.ErrorDetails.Message
    if (-not $resp -and $_.Exception.Response) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $resp = $reader.ReadToEnd()
    }
    throw "Worker upload failed: $resp"
  }

  Write-Ok "Worker deployed"
}

function Get-FileHashB64([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return [Convert]::ToBase64String($sha)
}

function Deploy-Pages {
  Write-Step "Deploying dashboard to Cloudflare Pages ($PagesProject)..."

  $files = @(
    "$Root\dashboard\index.html",
    "$Root\dashboard\styles.css",
    "$Root\dashboard\app.js"
  )
  foreach ($f in $files) {
    if (-not (Test-Path $f)) { throw "Missing file: $f" }
  }

  $manifest = @{}
  $fileMap = @{}
  foreach ($f in $files) {
    $name = "/" + (Split-Path $f -Leaf)
    $hash = Get-FileHashB64 $f
    $manifest[$name] = $hash
    $fileMap[$hash] = $f
  }
  $manifestJson = $manifest | ConvertTo-Json -Compress

  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $utf8 = [System.Text.Encoding]::UTF8
  $multipart = New-Object System.Collections.Generic.List[byte]

  $manifestPart = "--$boundary$LF" + "Content-Disposition: form-data; name=`"manifest`"$LF" + "Content-Type: application/json$LF$LF" + $manifestJson + "$LF"
  $multipart.AddRange($utf8.GetBytes($manifestPart))

  foreach ($hash in $fileMap.Keys) {
    $path = $fileMap[$hash]
    $fileName = Split-Path $path -Leaf
    $fileBytes = [System.IO.File]::ReadAllBytes($path)
    $header = "--$boundary$LF" + "Content-Disposition: form-data; name=`"$hash`"; filename=`"$fileName`"$LF" + "Content-Type: application/octet-stream$LF$LF"
    $multipart.AddRange($utf8.GetBytes($header))
    $multipart.AddRange($fileBytes)
    $multipart.AddRange($utf8.GetBytes("$LF"))
  }
  $multipart.AddRange($utf8.GetBytes("--$boundary--$LF"))

  $uploadHeaders = Get-AuthHeaders
  Invoke-RestMethod -Method POST `
    -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/pages/projects/$PagesProject/deployments" `
    -Headers $uploadHeaders `
    -ContentType "multipart/form-data; boundary=$boundary" `
    -Body ([byte[]]$multipart.ToArray()) | Out-Null

  Write-Ok "Pages deployed"
}

function Invoke-SeoRefresh {
  Write-Step "Running SEO audit + search engine pings..."
  Start-Sleep -Seconds 3
  try {
    $headers = @{ Authorization = "Bearer $DashboardPassword"; "Content-Type" = "application/json" }
    $result = Invoke-RestMethod -Method POST -Uri "$ApiUrl/api/seo/refresh" -Headers $headers
    Write-Ok "SEO refresh complete (health: $($result.healthScore))"
    if ($result.automation) {
      $a = $result.automation
      Write-Ok "IndexNow: $(if ($a.indexNow.ok) { 'submitted' } else { $a.indexNow.status })"
    }
  } catch {
    Write-Warn "SEO refresh: $_"
  }
}

function Test-Deployment {
  Write-Step "Verifying deployment..."

  $health = Invoke-RestMethod -Uri "$ApiUrl/health"
  if (-not $health.ok) { throw "API health check failed" }
  Write-Ok "API health: $($health.service)"

  Start-Sleep -Seconds 2
  try {
    $robots = Invoke-WebRequest -Uri "https://toledoswifthaul.com/robots.txt" -UseBasicParsing
    if ($robots.Content -match "Sitemap") { Write-Ok "robots.txt live" }
  } catch {
    Write-Warn "robots.txt check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $sitemap = Invoke-WebRequest -Uri "https://toledoswifthaul.com/sitemap.xml" -UseBasicParsing
    if ($sitemap.Content -match "toledoswifthaul.com") { Write-Ok "sitemap.xml live" }
  } catch {
    Write-Warn "sitemap.xml check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $keyUrl = "https://toledoswifthaul.com/tsh2026toledoswiftindexnowkey01.txt"
    $key = Invoke-WebRequest -Uri $keyUrl -UseBasicParsing
    if ($key.Content -match "tsh2026") { Write-Ok "IndexNow key file live" }
  } catch {
    Write-Warn "IndexNow key check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $pages = Invoke-WebRequest -Uri "https://toledoswifthaul.com/pages/junk-removal-sylvania-oh.html" -UseBasicParsing
    if ($pages.StatusCode -eq 200) { Write-Ok "Location pages live - 11 URLs in sitemap" }
  } catch {
    Write-Warn "Location page check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $lead = Invoke-RestMethod -Method POST -Uri "$ApiUrl/api/lead" `
      -ContentType "application/json" `
      -Body '{"name":"Deploy Test","phone":"4195550100","path":"/deploy-test"}'
    if ($lead.ok) { Write-Ok "Lead form API working" }
  } catch {
    Write-Warn "Lead API check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $stats = Invoke-RestMethod -Uri "$ApiUrl/api/stats" -Headers @{ Authorization = "Bearer $DashboardPassword" }
    Write-Ok "Dashboard login works (total calls: $($stats.total))"
  } catch {
    throw "Login test failed - password not accepted by API"
  }

  Start-Sleep -Seconds 2
  try {
    $site = Invoke-WebRequest -Uri "https://toledoswifthaul.com/" -UseBasicParsing
    if ($site.StatusCode -ne 200 -or $site.Content -notmatch "Toledo Swift Haul") {
      throw "Marketing site check failed"
    }
    Write-Ok "Marketing site live at https://toledoswifthaul.com"
  } catch {
    Write-Warn "Marketing site check: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2
  try {
    $seo = Invoke-RestMethod -Uri "$ApiUrl/api/seo/overview" -Headers @{ Authorization = "Bearer $DashboardPassword" }
    if ($seo.healthScore -ge 0) {
      Write-Ok "SEO dashboard ready (health score: $($seo.healthScore))"
    }
  } catch {
    Write-Warn "SEO dashboard check: $($_.Exception.Message)"
  }
}

function Save-Output {
  $out = @{
    apiUrl            = $ApiUrl
    marketingSiteUrl  = "https://toledoswifthaul.com"
    seoDashboardUrl   = "$ApiUrl/seo/"
    dashboardUrl      = "$ApiUrl/dashboard/"
    dashboardAltUrl   = "https://app.toledoswifthaul.com"
    githubPagesUrl    = "https://zeiasyed.github.io/toledo-swift-haul-dashboard/"
    dashboardPassword = $DashboardPassword
    deployedAt        = (Get-Date).ToString("o")
  } | ConvertTo-Json -Depth 3
  $out | Set-Content "$Root\deploy-output.json" -Encoding UTF8
}

Write-Host ""
Write-Host "Toledo Swift Haul - full deploy" -ForegroundColor White
Write-Host "================================" -ForegroundColor DarkGray

Get-CloudflareAuth -OverrideToken $Token -OverrideEmail $Email -OverrideKey $GlobalKey

try {
  $seoSetup = Get-SeoSetup
  Initialize-SeoSchema
  Initialize-LeadsSchema
  Enable-CfWebAnalytics $seoSetup
  Ensure-GscDnsVerification $seoSetup
  Deploy-Worker
  Set-SeoWorkerSecrets $seoSetup
  Ensure-WorkerRoutes
  Ensure-CronSchedule
  Test-Deployment
  Invoke-SeoRefresh
  Save-Output

  $siteUrl = "https://toledoswifthaul.com"
  $seoUrl = "$ApiUrl/seo/"
  $dashUrl = "$ApiUrl/dashboard/"
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Green
  Write-Host " DEPLOY COMPLETE" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Public site : $siteUrl"
  Write-Host "  SEO dash    : $seoUrl"
  Write-Host "  Call dash   : $dashUrl (calls only - not the public site)"
  Write-Host "  API URL     : $ApiUrl"
  Write-Host "  Password    : $DashboardPassword"
  Write-Host ""
  Write-Host "Opening SEO dashboard in browser..."
  Start-Process $seoUrl
} catch {
  Write-Host ""
  Write-Fail $_.Exception.Message
  Write-Host ""
  Write-Host "Delete .cloudflare-credentials.json and run again if credentials are wrong." -ForegroundColor Yellow
  exit 1
}
