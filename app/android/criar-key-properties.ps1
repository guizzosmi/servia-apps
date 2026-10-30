<#
  ServPilot - grava o android\key.properties (guia 41)
  Pergunta as senhas da chave de upload e grava o arquivo que o Gradle usa
  para assinar o app da loja. O arquivo fica FORA do Git (.gitignore).
  Rode na pasta servia-apps\app\android:   .\criar-key-properties.ps1
#>
param([string]$Chave = 'C:\dev\chaves\servpilot-upload.jks', [string]$Apelido = 'upload')
if (-not (Test-Path $Chave)) { Write-Host "Não achei a chave em $Chave (Parte A1 do guia 41)." -ForegroundColor Red; exit 1 }
$s1 = Read-Host 'Senha do arquivo da chave (storePassword)' -AsSecureString
$s2 = Read-Host 'Senha da chave (keyPassword; Enter = a mesma)' -AsSecureString
$t1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
$t2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
if (-not $t2) { $t2 = $t1 }
$conteudo = @(
  "storeFile=$($Chave -replace '\\', '/')",
  "storePassword=$t1",
  "keyAlias=$Apelido",
  "keyPassword=$t2"
) -join "`n"
Set-Content -Path (Join-Path $PSScriptRoot 'key.properties') -Value $conteudo -Encoding ASCII
Write-Host 'key.properties gravado (fora do Git).' -ForegroundColor Green
