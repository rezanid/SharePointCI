# Requires:
# Log.ps1

function Invoke-Actions{
	param(
		[System.Xml.XmlElement]$actionsRoot,
		[string]$progressTitle
	)

	$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
	$actionDefinitionsPath = Join-Path -Path $scriptPath -ChildPath SupportedActions.xml
	$actionDefinitions = [xml](Get-Content $actionDefinitionsPath)
	#$validActions = "Features", "IIS", "TimerJobs", "Provision", "Variation", "HostsFile"
	#$actionsRoot.ChildNodes | Where-Object { $validActions -contains $_.Name } |
	$actionsRoot.SelectNodes("./*") |
	ForEach-Object {
		$actionConfig = $_
		$actionDefinition = $actionDefinitions.SelectSingleNode("./SupportedActions/Action[@Name='$($_.LocalName)']")
		if ($actionDefinition) {
			Log "Information" "$progressTitle > $($actionConfig.LocalName)..."

			# Run action's script file if required
			if ($actionDefinition.ScriptPath) {
				$actionScriptPath = Join-Path $scriptPath -ChildPath $actionDefinition.ScriptPath
				#Invoke-Command -ScriptBlock [scriptblock]::Create(". `"$actionScriptPath`"")
				Invoke-Expression ". ""$actionScriptPath"""
			}

			# Figure out if the action needs root or children of config
			$command = Get-Command $actionDefinition.Command
			$config = if ($command.Parameters["Config"].ParameterType -eq [System.Xml.XmlElement]) { $actionConfig } else { $actionConfig.SelectNodes("./*") }

			# Build up parameters
			$params = @{Config = $config; ProgressTitle = "$progressTitle > $($actionConfig.LocalName)"; ActionDefinition = $actionDefinition}

			# Run the command
			&($actionDefinition.Command) @params

			Log "Information" "$progressTitle > $($actionConfig.LocalName) done."
		} else {
			Log "Critical" "$($_.LocalName) deployment action is not supported."
		}
	}
}

function Invoke-DynamicCommand {
	param(
		[string]$CommandName,
		[Hashtable]$CommandParameters,
		[string]$ContainingScriptPath
	)

	process {
		# Run action's script file if required
		if ($ContainingScriptPath) {
			$actionScriptPath = Join-Path $scriptPath -ChildPath $ContainingScriptPath
			#Invoke-Command -ScriptBlock [scriptblock]::Create(". $actionScriptPath")
			Invoke-Expression -ScriptBlock ". ""$actionScriptPath"""
		}

		# Run the command
		$scriptBlock = [scriptblock]::Create("&$CommandName @params")
		Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $CommandParameters
	}
}
