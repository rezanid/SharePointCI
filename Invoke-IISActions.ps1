# Requires:
# Log.ps1
# Get-WebPage.ps1
$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
. $scriptPath\Get-WebPage.ps1

function Invoke-IISActions([System.Xml.XmlElement]$Config, [string]$ProgressTitle) {
	[System.Xml.XmlNodeList]$iisActions = $Config.SelectNodes("./*")
	[int]$iisActionCount = $iisActions.Count
	[int]$iisActionIndex = 0

	if (-not(Get-Module "WebAdministration")) {
		if(Get-Module -ListAvailable | Where-Object { $_.Name -eq "WebAdministration" }) {
			Import-Module WebAdministration
		}
		else {
			Log "Warning" "IIS Actions are ignored since WebAdministration module is not available."
			return
		}
	}

	$iisActions | ForEach-Object {
		if ($_.LocalName -eq "Recycle") {
			# Report progress
			Write-Progress -Activity $ProgressTitle -Status "Recycling $($_.AppPool)" -PercentComplete ($iisActionIndex / $iisActionCount * 100)

			[string]$appPoolName = $_.AppPool
			try {
				Restart-WebAppPool $appPoolName
				Log "Information" "$appPoolName application pool recycled successfully."
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while recycling $appPoolName application pool. Please check the following logs for more details."
			}
		}
		elseif ($_.LocalName -eq "Warmup") {
			# Report progress
			Write-Progress -Activity $ProgressTitle -Status "Warming up $( $_.Url)" -PercentComplete ($iisActionIndex / $iisActionCount * 100)

			[string]$warmupUrl = $_.Url
			#Invoke-WebRequest $_.Url -UseDefaultCredentials -UseBasicParsing
			try {
				Get-WebPage $warmupUrl
				Log "Information" "Warmup action for $warmupUrl completed successfully."
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while runnign warmup on the following URL: $warmupUrl. Please check the following logs for more details."
			}
		}
		$iisActionIndex++
	}
	# Report progress (completed)
	Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed
}
