# Deploys the patch feed worker, sets bot secrets and registers the Telegram
# webhook. Idempotent: safe to re-run.
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
npx.cmd --yes wrangler@latest whoami 2>$null
if ($LASTEXITCODE -ne 0) {
    npx.cmd --yes wrangler@latest login
}

Write-Host "== secrets =="
$token = Need 'TELEGRAM_BOT_TOKEN'
$secret = Need 'TELEGRAM_WEBHOOK_SECRET'
$owner = Need 'TELEGRAM_OWNER_ID'

$token  | npx.cmd --yes wrangler@latest secret put TELEGRAM_BOT_TOKEN
$secret | npx.cmd --yes wrangler@latest secret put TELEGRAM_WEBHOOK_SECRET
$owner  | npx.cmd --yes wrangler@latest secret put TELEGRAM_OWNER_ID

Write-Host "== deploy =="
npx.cmd --yes wrangler@latest deploy | Out-Host

$toml = Get-Content 'wrangler.toml' -Raw
$workerUrl = ([regex]::Match($toml, 'PUBLIC_BASE_URL\s*=\s*"([^"]+)"')).Groups[1].Value
if (-not $workerUrl) { $workerUrl = Read-Host "Worker URL" }
Write-Host "worker: $workerUrl"

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
Write-Host "Keep this webhook secret identical on jvztxnx-global-control; the"
Write-Host "patch worker forwards non-patch updates through a service binding."
