# S2-05 · start_all.ps1：一键拉起 dev 环境（compose + envcheck + 全部服务）
# 用法：pwsh -File deploy/start_all.ps1 [-Profiles core,edge,obs] [-SkipEnvcheck]
# E9：路径含空格一律引号（"D:\Personal code\..." 即真实教训场景）。
param(
    [string]$Profiles = '',
    [switch]$SkipEnvcheck
)
$ErrorActionPreference = 'Stop'

$deployRoot = Split-Path -Parent $PSScriptRoot      # micro-deploy 根
$devRoot = Split-Path -Parent $deployRoot           # micro-new 根（各仓并列）
$composeDir = Join-Path $deployRoot 'compose\dev'
$composeFile = Join-Path $composeDir 'docker-compose.dev.yml'

# ---- 1) 中间件：compose up（profile 由参数或 .env 决定）----
Write-Host '== [1/3] docker compose up -d =='
Push-Location $composeDir
try {
    if ($Profiles) {
        $env:COMPOSE_PROFILES = $Profiles
    }
    docker compose -f "$composeFile" up -d
    if ($LASTEXITCODE -ne 0) { throw "compose up 失败（exit $LASTEXITCODE）" }
}
finally { Pop-Location }

# ---- 2) 健康等待 + envcheck ----
Write-Host '== [2/3] 等待容器 healthy + envcheck =='
$deadline = (Get-Date).AddMinutes(5)
Push-Location $composeDir
try {
    while ((Get-Date) -lt $deadline) {
        $bad = docker compose -f "$composeFile" ps --format json 2>$null |
            Where-Object { $_ -and ($_ | ConvertFrom-Json).Health -eq 'starting' }
        if (-not $bad) { break }
        Start-Sleep -Seconds 5
    }
    docker compose -f "$composeFile" ps
}
finally { Pop-Location }

if (-not $SkipEnvcheck) {
    Push-Location (Join-Path $devRoot 'micro-server')
    try { go run ./tools/envcheck; if ($LASTEXITCODE -ne 0) { throw 'envcheck 未通过——按失败项排查后再启动服务' } }
    finally { Pop-Location }
}

# ---- 3) 后端服务：逐个 restart-svc.ps1（S3 首个服务起生效）----
Write-Host '== [3/3] 后端服务 =='
$services = @(
    # S3 起在此登记，如：'identity', 'admin-bff'
)
if ($services.Count -eq 0) {
    Write-Host '（暂无登记的后端服务——S3-05 起在此数组登记，逐个调用 tools/restart-svc.ps1）'
}
else {
    foreach ($s in $services) {
        pwsh -File (Join-Path $devRoot 'micro-server\tools\restart-svc.ps1') $s
    }
}

Write-Host '== start_all 完成：Grafana http://127.0.0.1:23000 ｜ Jaeger http://127.0.0.1:36686 =='
