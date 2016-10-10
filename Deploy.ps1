# Run this script to start a new deployment.

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
$LogFilePath = Join-Path -Path $scriptPath -ChildPath Install.log
if (Test-Path $LogFilePath) { Remove-Item $LogFilePath -Confirm:$false }
. $scriptPath\Log.ps1
. $scriptPath\Invoke-Actions.ps1
. $scriptPath\Deploy-SPSolutions.ps1
Deploy-SPSolutions $scriptPath\Deployment.xml -Log $LogFilePath
. $LogFilePath

