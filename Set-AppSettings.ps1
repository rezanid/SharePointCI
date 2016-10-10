#Credit: https://blogs.msdn.microsoft.com/miguelnunez/2015/02/03/powershell-for-changing-appsettings-in-application-configuration-file/
function Set-AppSetting
{
	param (
		#[parameter(Mandatory = $true)][ValidateScript ({Test-Path $_})][string] $PathToConfigFile,
		[parameter(Mandatory = $true)][string] $PathToConfigFile,
		[parameter(Mandatory = $true)][string] $PropertyName,
		[parameter(Mandatory = $false)][string] $PropertyValue,
		#[Parameter(Mandatory = $false)][Validatescript ({(Get-Service $_) -ne $null})][string] $NameOfServiceToRestart = $null
		[Parameter(Mandatory = $false)][string] $NameOfServiceToRestart = $null
	)

	$configurationAppSettingXmlPath = "//configuration/appSettings"

	[xml] $configurationDocument = Get-Content $PathToConfigFile
	$appSettingsNode = $configurationDocument.SelectSingleNode($configurationAppSettingXmlPath)

	if($appSettingsNode -eq $null)
	{
		$(throw "AppSettings does not exist! Invalid configuration file.")
	}

	$nodeToUpdate = $configurationDocument.SelectSingleNode($configurationAppSettingXmlPath+"/add[@key='$PropertyName']")
	if($nodeToUpdate -ne $null)
	{
		Write-Host "[$PropertyName] Already exists, Removing it to re-add with new value."
		$removedElement = $appSettingsNode.RemoveChild($nodeToUpdate)
	}

	#Write-Host "Creating new configuration node."
	$newPropertyNode = $configurationDocument.CreateNode("element", "add","")

	#Write-Host "Setting node attributes."
	$newPropertyNode.SetAttribute("key", $PropertyName)
	$newPropertyNode.SetAttribute("value", $PropertyValue)

	#Write-Host "Appending child to AppSettings."
	$appSettingsNode = $configurationDocument.SelectSingleNode($configurationAppSettingXmlPath).AppendChild($newPropertyNode)

	#Write-Host "Adding new property into the configuration file."
	$configurationDocument.Save($PathToConfigFile)

	Write-Host "Property was successfully updated (name: $PropertyName, value: $PropertyValue)."

	#if([string]::IsNullOrWhiteSpace($NameOfServiceToRestart) -eq $false)
	if([string]::IsNullOrEmpty($NameOfServiceToRestart) -eq $false)
	{
		Write-Host "Service [$NameOfServiceToRestart] was defined.., restarting it"
		Restart-Service -Name $NameOfServiceToRestart
		Write-Host "Service was restarted"
	}
}
