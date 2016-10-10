# Requires:
# Log.ps1
function Build-ManagedPaths{
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$True)]
		[Microsoft.SharePoint.PowerShell.SPWebApplicationPipeBind]
		$WebApplication,
		[Parameter(Position=1, Mandatory=$true)]
		[System.Xml.XmlElement]
		$Config
	)

	process {
		$webApp = $WebApplication.Read()
		$Config.Path | ForEach-Object {
			$pathName = $_.RelativeUrl
			$managedPath = Get-SPManagedPath -WebApplication $webApp | Where-Object {$_.Name -eq $pathName}
			if (!$managedPath) {
				$pathParams = @{
					RelativeURL = $pathName
					WebApplication = $webApp
				}
				if ([System.Convert]::ToBoolean($_.Explicit)) { $pathParams.Add("Explicit", $null) }
				New-SPManagedPath @pathParams > $null
				Log "Information" "Managed path $($_.RelativeUrl) has been created successfully."
			} else {
				Log "Information" "Managed path $($_.RelativeUrl) already exists."
			}
		}
	}
}
