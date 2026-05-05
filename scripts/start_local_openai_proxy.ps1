param(
  [int]$Port = 8787,
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Get-OpenAiKeyFromText([string]$Raw) {
  if ([string]::IsNullOrWhiteSpace($Raw)) {
    return ""
  }

  $assigned = [regex]::Match($Raw, "(?m)^\s*OPENAI_API_KEY\s*=\s*(.+?)\s*$")
  if ($assigned.Success) {
    $value = $assigned.Groups[1].Value.Trim().Trim('"').Trim("'")
    if ($value.StartsWith("sk-")) {
      return $value
    }
  }

  $loose = [regex]::Match($Raw, "\bsk-[A-Za-z0-9_-]{20,}\b")
  if ($loose.Success) {
    return $loose.Value
  }

  return ""
}

try {
  $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
  if ($health.ok) {
    Write-Output "Local_OpenAI_proxy_already_running_http://127.0.0.1:$Port"
    exit 0
  }
} catch {
  $busy = netstat -ano | Select-String ":$Port" | Select-String "LISTENING"
  if ($busy) {
    throw "Port $Port is already in use, but it is not the current StarTrack AI proxy. Run: .\scripts\Run-StarTrackAI.ps1 stop"
  }
}

$apiKeyPath = Join-Path $ProjectRoot "Open API.txt"
if (-not (Test-Path $apiKeyPath)) {
  throw "Open API.txt not found at $apiKeyPath"
}

$env:OPENAI_API_KEY = Get-OpenAiKeyFromText (Get-Content $apiKeyPath -Raw)
if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
  throw "No OpenAI API key was found in Open API.txt"
}

$env:OPENAI_PROXY_PORT = "$Port"
Set-Location (Join-Path $ProjectRoot "functions")
node .\local-proxy.js
