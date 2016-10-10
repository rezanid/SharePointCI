# Requires:
# Log.ps1

function Invoke-SPFeatures{
	param(
		[System.Xml.XmlElement]$Config,
		[string]$ProgressTitle
	)

	$featureActions = $Config.SelectNodes("./*")
	[int]$featureCount = $featureActions.Count
	[int]$featureIndex = 0

	$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
	if(-not(Get-PSSessionConfiguration | Where-Object {$_.Name -eq "PS2"})) {
			Register-PSSessionConfiguration -Name PS2 -Confirm:$false -SecurityDescriptorSddl "O:NSG:BAD:P(A;;GA;;;BA)S:P(AU;FA;GA;;;WD)(AU;SA;GXGW;;;WD)"
	}

	#Open a new session (process: wsmprovhost.exe)
	$session = New-PSSession -ConfigurationName "PS2"
	Invoke-Command -Session $session -ScriptBlock $snapin

	Write-Output "Waiting 10sec for debugger..."
	sleep 10
	Write-Output "Waiting finished."

	$featureActions | Where-Object {($_.LocalName -eq "activate") -or ($_.LocalName -eq "deactivate") } | ForEach-Object {
		$featureIndex++
		[bool]$featureActivate = $_.LocalName -eq "activate"
		[string]$featureId = $_.Id
		[string]$featureDesc = $_.Description
		[string]$featureUrl = ""

		if ($featureActivate) {
			# Report progress
			Write-Progress -Activity $ProgressTitle -Status "Activating $featureDesc" -PercentComplete ($featureIndex / $featureCount * 100)
			try {
				# Check if there is a URL
				if (![string]::IsNullOrEmpty($_.Url)) {
					$featureUrl = $_.Url
					# WebApp / Site / Web scoped feature
					Log "Information" "Activating $featureDesc ($featureId) on $featureUrl..."
					$command = {
							param($featureId, $featureUrl)
							Enable-SPFeature -Id $featureId -Url $featureUrl -Confirm:$false -PassThru -Force > $null
					}
					Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId, $featureUrl -ErrorVariable featureErrors
				}
				else {
					# Farm scoped feature
					Log "Information" "Activating $featureDesc ($featureId) on farm..."
					$command = {
						param($featureId)
						Enable-SPFeature -Id $featureId -Confirm:$false -PassThru -Force > $null
					}
					Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId -ErrorVariable featureErrors
				}
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while ACTIVATING $featureId. Please check the following logs for more details."
			}
#				if ($featureErrors -and $featureErrors.Count -gt 0) {
#					$featureErrors | ForEach-Object {
#						Log-Error $_ "An exception has been thrown while ACTIVATING $featureId. Please check the following logs for more details."
#					}
#				}
#				else {
			if ($featureErrors -eq $null -or $featureErrors.Count -eq 0) {
					Log "Information" "Feature has been activated successfully."
			}
		}
		else {
			# Report progress
			Write-Progress -Activity $ProgressTitle -Status "Deactivating $featureDesc" -PercentComplete ($featureIndex / $featureCount * 100)
			try {
				# Check if there is a URL
				if (![string]::IsNullOrEmpty($_.Url)) {
					$featureUrl = $_.Url
					# WebApp / Site / Web scoped feature
					Log "Information" "Deactivating $featureDesc ($featureId) on $featureUrl..."
					$feature = Get-SPFeature $featureId -ErrorAction SilentlyContinue
					if ($feature) {
						$command = {
							param($featureId, $featureUrl)
							Disable-SPFeature -Id $featureId -Url $featureUrl -Confirm:$false
						}
						Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId, $featureUrl -ErrorVariable featureErrors
						Log "Information" "Feature has been deactivated successfully."
					}
					else {
						Log "Information" "Feature deactivation has been skipped since no feature has been found with the following ID: $featureId"
					}
				}
				else {
					# Farm scoped feature
					Log "Information" "Deactivating $featureDesc ($featureId) on farm..."
					$command = {
						param($featureId)
						Disable-SPFeature -Id $featureId -Confirm:$false
					}
					Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId -ErrorVariable featureErrors
					Log "Information" "Feature has been deactivated successfully"
				}
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while DEACTIVATING $featureId. Please check the following logs for more details."
			}
		}
	}

	if ($session) { Remove-PSSession $session }
	#Unregister-PSSessionConfiguration -Name "powershell2" -Confirm:$false

	# Report progress (completed)
	Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed
}
