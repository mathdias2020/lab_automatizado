param(
    [string]$SourcePath = 'C:\Users\Windows 11\Desktop\Projeto-Fluxo-WDO-WIN\dados_parquet',
    [string]$SshKey = 'C:\Users\Windows 11\.ssh\lab_indicadores_codex',
    [string]$HostName = '187.127.14.250',
    [string]$UserName = 'labadmin',
    [string]$Destination = '/srv/labs/datasets/raw/full.incoming'
)

$ErrorActionPreference = 'Stop'
$source = Get-Item -LiteralPath $SourcePath
& ssh -i $SshKey -o IdentitiesOnly=yes "$UserName@$HostName" "mkdir -p $Destination"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

foreach ($assetDirectory in Get-ChildItem -LiteralPath $source.FullName -Directory) {
    & scp -r -i $SshKey -o IdentitiesOnly=yes $assetDirectory.FullName "${UserName}@${HostName}:$Destination/"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& ssh -i $SshKey -o IdentitiesOnly=yes "$UserName@$HostName" "touch $Destination/.transfer-complete"
exit $LASTEXITCODE
