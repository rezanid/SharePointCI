# Requires:
# Log.psq
# Set-HostsEntry.sp1
$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
. $scriptPath\Set-HostsEntry.ps1

function Invoke-HostsFileActions([System.Xml.XmlElement]$Config, [string]$ProgressTitle) {
	[System.Xml.XmlNodeList]$hostEntries = $Config.SelectNodes("./*")
	[int]$hostEntryCount = $hostEntries.Count
	[int]$hostEntryIndex = 0

	# Report progress
	Write-Progress -Activity $ProgressTitle -Status "Setting host file entries" -PercentComplete ($hostEntryIndex / $hostEntryCount * 100)

	$hostEntries | ForEach-Object {
		if ($_.LocalName -eq "Entry") {
			try {
				Set-HostsEntry -IPAddress $_.IPAddress -HostName $_.HostName
				Log "Information" "$($_.HostName) ($($_.IPAddress)) host entry set successfully."
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while wrting hosts file entry ($($_.HostName) -> $($_.IPAddress)). Please check the following logs for more details."
			}
		}
		$hostEntryIndex++

		# Report progress
		Write-Progress -Activity $ProgressTitle -Status "Recycling $($_.AppPool)" -PercentComplete ($iisActionIndex / $hostEntryCount * 100)
	}

	# Report progress (completed)
	Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed
}
