# Requires:
# Log.ps1

function Invoke-ProvisionActions {
	param(
		[System.Xml.XmlElement]$Config,
		[string]$ProgressTitle,
		[System.Xml.XmlElement]$ActionDefinition
	)

	$provisionActions = $Config.SelectNodes("./*")

	[int]$provisionCount = $provisionActions.Count
	[int]$provisionIndex = 0

	$provisionActions | ForEach-Object {
		# Report progress
		Write-Progress -Activity $ProgressTitle -Status "Provisioning $($_.LocalName)" -PercentComplete ($provisionIndex / $provisionCount * 100)

		$subActionConfig = $_
		$subActionDefinition = $ActionDefinition.SelectSingleNode("./Action[@Name='$($subActionConfig.LocalName)']")
		if ($subActionDefinition) {
			Log "Information" "$progressTitle > $($subActionConfig.LocalName)..."

			# Run action's script file if required
			if ($subActionDefinition.ScriptPath) {
				$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
				$subActionScriptPath = Join-Path $scriptPath -ChildPath $subActionDefinition.ScriptPath
				#Invoke-Command -ScriptBlock [scriptblock]::Create(". $actionScriptPath")
				Invoke-Expression ". ""$subActionScriptPath"""
			}

			# Build up parameters
			$params = @{Config = $subActionConfig; ProgressTitle = "$ProgressTitle > $($actionConfig.LocalName)..."; ActionDefinition = $subActionDefinition}

			# Run the command
			&($subActionDefinition.Command) @params

			Log "Information" "$progressTitle > $($subActionConfig.LocalName) done."
		} else {
			Log "Critical" "$($Config.LocalName)\$($subActionConfig.LocalName) deployment action is not supported."
		}

		$provisionIndex++
	}

	# Report progress (completed)
	Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed
}
