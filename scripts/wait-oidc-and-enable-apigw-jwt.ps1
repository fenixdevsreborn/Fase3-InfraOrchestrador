# Aguarda OIDC da Users API e aplica Terraform com JWT no API Gateway.
# Executar na raiz do repositório Fase3-InfraOrchestrador.
# Uso: .\scripts\wait-oidc-and-enable-apigw-jwt.ps1 [-MaxMinutes 20]

param(
    [int] $MaxMinutes = 20
)

$ErrorActionPreference = "Stop"
$TfDir = Join-Path $PSScriptRoot "..\terraform\environments\production" | Resolve-Path
Set-Location $TfDir

if (-not (Test-Path "terraform.tfvars")) {
    Write-Error "Crie terraform.tfvars em $TfDir"
}

terraform init -input=false | Out-Host
$invoke = (terraform output -raw api_gateway_invoke_url).TrimEnd("/")
$oidc = "$invoke/users/.well-known/openid-configuration"
Write-Host "OIDC: $oidc"

$maxSec = $MaxMinutes * 60
$elapsed = 0
$sleepSec = 15

while ($elapsed -lt $maxSec) {
    try {
        $r = Invoke-WebRequest -Uri $oidc -Method Get -TimeoutSec 30 -UseBasicParsing
        if ($r.StatusCode -eq 200) {
            Write-Host "OIDC OK."
            terraform apply -auto-approve -input=false `
                -var-file=terraform.tfvars `
                -var=api_gateway_jwt_authorizer_enabled=true
            exit 0
        }
    } catch {
        Write-Host "Aguardando OIDC... (${elapsed}s / ${maxSec}s)"
    }
    Start-Sleep -Seconds $sleepSec
    $elapsed += $sleepSec
}

Write-Error "Timeout após $MaxMinutes min. Verifique Users API (PathBase /users, Jwt__Issuer)."
