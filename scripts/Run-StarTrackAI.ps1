param(
  [ValidateSet('web', 'android', 'apk-debug', 'debug', 'apk-local', 'release', 'apk-cloud', 'deploy-cloud', 'proxy', 'prepare-android', 'stop')]
  [string]$Mode = 'web',
  [string]$Device = '',
  [int]$Port = 8787,
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
  Write-Host "[StarTrack AI] $Message"
}

function Get-ProxyBaseUrl {
  return "http://127.0.0.1:$Port"
}

function Get-ProxyHealthUrl {
  return "$(Get-ProxyBaseUrl)/health"
}

function Test-ProxyReady {
  try {
    $response = Invoke-RestMethod -Method Get -Uri (Get-ProxyHealthUrl) -TimeoutSec 2
    return [bool]$response.ok
  } catch {
    return $false
  }
}

function Get-ProxyProcessIds {
  $rows = netstat -ano | Select-String ":$Port"
  $processIds = @()
  foreach ($row in $rows) {
    $text = $row.ToString()
    if ($text -match '\sLISTENING\s+(\d+)\s*$') {
      $processIds += [int]$Matches[1]
    }
  }
  return $processIds | Select-Object -Unique
}

function Ensure-Proxy {
  if (Test-ProxyReady) {
    Write-Step "Local AI proxy already running at $(Get-ProxyBaseUrl)"
    return
  }

  $staleProcessIds = @(Get-ProxyProcessIds)
  if ($staleProcessIds.Count -gt 0) {
    Write-Step "Port $Port is busy but not serving the current AI proxy. Restarting it..."
    foreach ($processId in $staleProcessIds) {
      Stop-Process -Id $processId -Force
    }
    Start-Sleep -Milliseconds 500
  }

  $scriptPath = Join-Path $ProjectRoot 'scripts\start_local_openai_proxy.ps1'
  if (-not (Test-Path $scriptPath)) {
    throw "Proxy starter not found: $scriptPath"
  }

  Write-Step "Starting local AI proxy in the background..."
  Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      $scriptPath,
      '-Port',
      $Port,
      '-ProjectRoot',
      $ProjectRoot
    ) `
    -WindowStyle Hidden | Out-Null

  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-ProxyReady) {
      Write-Step "Local AI proxy ready at $(Get-ProxyBaseUrl)"
      return
    }
  }

  throw "Local AI proxy did not become ready. Run scripts\start_local_openai_proxy.ps1 once to see the error."
}

function Stop-Proxy {
  $processIds = @(Get-ProxyProcessIds)
  if ($processIds.Count -eq 0) {
    Write-Step "No local AI proxy found on port $Port."
    return
  }

  foreach ($processId in $processIds) {
    Stop-Process -Id $processId -Force
  }
  Write-Step "Stopped local AI proxy on port $Port."
}

function Get-AdbPath {
  $command = Get-Command adb -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($root in $sdkRoots) {
    $candidate = Join-Path $root 'platform-tools\adb.exe'
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $defaultCandidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
  if (Test-Path $defaultCandidate) {
    return $defaultCandidate
  }

  return ''
}

function Enable-AndroidReverse {
  $adb = Get-AdbPath
  if ([string]::IsNullOrWhiteSpace($adb)) {
    Write-Step "adb not found. Android will use Flutter defaults; install Android platform-tools for network-proof localhost AI."
    return
  }

  $rawDevices = & $adb devices | Select-Object -Skip 1
  $deviceIds = @()
  foreach ($line in $rawDevices) {
    if ($line -match '^([^\s]+)\s+device$') {
      $deviceIds += $Matches[1]
    }
  }

  if ($Device -and $Device -ne 'android') {
    $deviceIds = @($Device)
  }

  if ($deviceIds.Count -eq 0) {
    Write-Step "No adb device is online yet. Flutter may wait for one."
    return
  }

  foreach ($deviceId in $deviceIds) {
    & $adb -s $deviceId reverse "tcp:$Port" "tcp:$Port" | Out-Null
    Write-Step "ADB reverse enabled for ${deviceId}: device localhost:$Port -> PC localhost:$Port"
  }
}

function Invoke-Flutter([string[]]$FlutterArgs) {
  Set-Location $ProjectRoot
  & flutter @FlutterArgs
}

$proxyBase = Get-ProxyBaseUrl
$commonDefines = @(
  "--dart-define=OPENAI_PROXY_BASE_URL=$proxyBase",
  "--dart-define=FIREBASE_PROJECT_ID=star-track-4ba2b"
)

$cloudProxyBase = 'https://us-central1-star-track-4ba2b.cloudfunctions.net'
$cloudDefines = @(
  "--dart-define=OPENAI_PROXY_BASE_URL=$cloudProxyBase",
  "--dart-define=FIREBASE_PROJECT_ID=star-track-4ba2b"
)

switch ($Mode) {
  'proxy' {
    Ensure-Proxy
    Write-Step "Proxy only mode. AI endpoints are under $proxyBase"
  }
  'prepare-android' {
    Ensure-Proxy
    Enable-AndroidReverse
    Write-Step "Android AI is prepared. Use proxy base $proxyBase in Flutter defines."
  }
  'stop' {
    Stop-Proxy
  }
  'web' {
    Ensure-Proxy
    $flutterArgs = @('run', '-d', 'chrome') + $commonDefines
    Invoke-Flutter $flutterArgs
  }
  'android' {
    Ensure-Proxy
    Enable-AndroidReverse
    $targetDevice = if ([string]::IsNullOrWhiteSpace($Device)) { 'android' } else { $Device }
    $flutterArgs = @('run', '-d', $targetDevice) + $commonDefines
    Invoke-Flutter $flutterArgs
  }
  'apk-debug' {
    Ensure-Proxy
    Enable-AndroidReverse
    $flutterArgs = @('build', 'apk', '--debug') + $commonDefines
    Invoke-Flutter $flutterArgs
    Write-Step "Built a local-proxy debug APK at build\app\outputs\flutter-apk\app-debug.apk"
  }
  'debug' {
    Ensure-Proxy
    Enable-AndroidReverse
    $flutterArgs = @('build', 'apk', '--debug') + $commonDefines
    Invoke-Flutter $flutterArgs
    Write-Step "Built a local-proxy debug APK at build\app\outputs\flutter-apk\app-debug.apk"
  }
  'apk-local' {
    Ensure-Proxy
    Enable-AndroidReverse
    $flutterArgs = @('build', 'apk', '--release') + $commonDefines
    Invoke-Flutter $flutterArgs
    Write-Step "Built a local-proxy APK. Keep USB debugging + adb reverse active while testing local AI."
  }
  'release' {
    $flutterArgs = @('build', 'apk', '--release') + $cloudDefines
    Invoke-Flutter $flutterArgs
    Write-Step "Built release APK with Cloud AI endpoints: $cloudProxyBase"
  }
  'apk-cloud' {
    $flutterArgs = @('build', 'apk', '--release') + $cloudDefines
    Invoke-Flutter $flutterArgs
    Write-Step "Built release APK with Cloud AI endpoints: $cloudProxyBase"
  }
  'deploy-cloud' {
    Set-Location (Join-Path $ProjectRoot 'functions')
    & firebase deploy --only functions --project star-track-4ba2b
  }
}
