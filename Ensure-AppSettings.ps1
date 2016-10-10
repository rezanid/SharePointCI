# Requires:
# Log.ps1
$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
. $scriptPath\Set-AppSetting.ps1

function Ensure-AppSettings{
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
		[Microsoft.SharePoint.PowerShell.SPWebApplicationPipeBind]
		$WebApplication,
		[Parameter(Position=1, Mandatory=$true)]
		[System.Xml.XmlElement]
		$Config
	)

	process {
		$webApp = $WebApplication.Read()
		$appSettings = $Config.SelectNodes("./add")
		$webApp.IisSettings.Count
		$webApp.IisSettings.Values | ForEach-Object {
			$configFilePath = Join-Path -Path ($_.Path.FullName) -ChildPath web.config
			$appSettings | ForEach-Object {
				Set-AppSetting -PathToConfigFile $configFilePath -PropertyName $_.Key -PropertyValue $_.Value
			}
			Log [Information] "AppSettings has been synchronized successfully in $configFilePath."
		}
	}
}
