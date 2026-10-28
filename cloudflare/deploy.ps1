# Deploys the patch feed worker, creates the R2 bucket, sets bot secrets and
# registers the Telegram webhook. Idempotent: safe to re-run.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1
#
# Secrets can be supplied through the environment first to skip prompts:
#   $env:TELEGRAM_BOT_TOKEN="..."
#   $env:TELEGRAM_WEBHOOK_SECRET="..."
#   $env:TELEGRAM_OWNER_ID="..."

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Need($name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $secure = Read-Host -Prompt $name -AsSecureString
        $value = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$name is required" }
    return $value
}

Write-Host "== node =="
node --version

Write-Host "== wrangler login =="
npx --yes wrangler@latest whoami 2>$null
if ($LASTEXITCODE -ne 0) {
    npx --yes wrangler@latest login
}

Write-Host "== r2 bucket =="
npx --yes wrangler@latest r2 bucket create trystore-patches
if ($LASTEXITCODE -ne 0) {
    Write-Host "bucket may already exist, continuing"
}

Write-Host "== secrets =="
$token = Need 'TELEGRAM_BOT_TOKEN'
$secret = Need 'TELEGRAM_WEBHOOK_SECRET'
$owner = Need 'TELEGRAM_OWNER_ID'

$token  | npx --yes wrangler@latest secret put TELEGRAM_BOT_TOKEN
$secret | npx --yes wrangler@latest secret put TELEGRAM_WEBHOOK_SECRET
$owner  | npx --yes wrangler@latest secret put TELEGRAM_OWNER_ID

Write-Host "== deploy =="
$deployOutput = npx --yes wrangler@latest deploy 2>&1 | Tee-Object -Variable deploy
$deployOutput

$workerUrl = ($deploy | Select-String -Pattern 'https://[a-z0-9.\-]+\.workers\.dev' |
    Select-Object -First 1).Matches.Value
if (-not $workerUrl) {
    $workerUrl = Read-Host "Worker URL (from deploy output)"
}
Write-Host "worker: $workerUrl"

Write-Host "== set public base url =="
$toml = Get-Content 'wrangler.toml' -Raw
$toml = $toml -replace 'PUBLIC_BASE_URL = ".*"', "PUBLIC_BASE_URL = `"$workerUrl`""
Set-Content 'wrangler.toml' -Value $toml -NoNewline
npx --yes wrangler@latest deploy | Out-Host

Write-Host "== telegram webhook =="
$body = @{
    url = "$workerUrl/api/telegram/webhook"
    secret_token = $secret
    allowed_updates = @('message', 'callback_query')
} | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/setWebhook" -Body $body -ContentType 'application/json' | ConvertTo-Json -Depth 4

Write-Host "== health =="
Invoke-RestMethod "$workerUrl/health" | ConvertTo-Json -Compress

Write-Host ""
Write-Host "Manifest: $workerUrl/api/patches/trystore/manifest.json"
Write-Host "If that origin differs from the Swift constant, update:"
Write-Host "  ThreeOneOSFive/helpers/PatchFeedService.swift -> baseURL"
