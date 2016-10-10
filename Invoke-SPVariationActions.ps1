# Requires:
# Log.ps1

function Invoke-SPVariationActions([System.Xml.XmlElement]$Config, [string]$progressTitle) {
	$variationActions = $Config.SelectNodes("./*")
	# Number of actions = labels + 1 (to setup variation)
	[int]$variationCount = $variationActions.Count + 1
	[int]$variationIndex = 0

	# Report progress
	Write-Progress -Activity $progressTitle -Status "Configuring variation" -PercentComplete ($variationIndex / $variationCount * 100)

	# Configure Variations
	$gc = Start-SPAssignment
	$rootWeb = $gc | Get-SPWeb $_.SiteUrl
	$relationListId = [Guid]($rootWeb.GetProperty("_VarRelationshipsListId"))
	$relationList = $rootWeb.Lists[$relationListId]
	$rootFolder = $relationList.RootFolder

	# Validation
	if (!$relationListId) {
		Log-Error "Critical" "$($_.SiteUrl) is not a publishing site and it is not possible to enable variation for it."
		throw [System.ArgumentException] "`$Config.SiteUrl is not pointing to a valid publishing site collection."
	}

	# Automatic creation (e.g. True)
	$rootFolder.SetProperty("EnableAutoSpawnPropertyName", $_.AutoSpawn)
	# Recreate Deleted Target Page; set to false to enable recreation (e.g. False)
	$rootFolder.SetProperty("AutoSpawnStopAfterDeletePropertyName", $_.AutoSpawnStopAfterDelete)
	# Update Target Page Web Parts (e.g. True)
	$rootFolder.SetProperty("UpdateWebPartsPropertyName", $_.UpdateWebParts)
	# Resources (e.g. False)
	$rootFolder.SetProperty("CopyResourcesPropertyName", $_.CopyResources)
	# Notification (e.g. False)
	$rootFolder.SetProperty("SendNotificationEmailPropertyName", $_.SendNotificationEmail)
	# Site Template (e.g. CMSPUBLISHING#0)
	$rootFolder.SetProperty("SourceVarRootWebTemplatePropertyName", $_.SourceVarRootWebTemplate)
	$rootFolder.Update()
	Log "Information" "Variation settings have been updated successfully."

	if ($relationList.ItemCount -le 0) {
		$relationItem = $relationList.AddItem()
		$relationItem["GroupGuid"] = [Guid]("F68A02C8-2DCC-4894-B67D-BBAED5A066F9")
		$relationItem["Deleted"] = $false
		$relationItem["ParentAreaID"] = ""
		Log "Information" "Variation root has been set successfully."
	}
	else {
		$relationItem = $relationList.GetItemById(1)
	}
	$relationItem["ObjectID"] = $_.Home
	$relationItem.Update()

	# Labels
	$labelListId = [Guid]($rootWeb.GetProperty("_VarLabelsListId"))
	$labelList = $rootWeb.Lists[$labelListId]
	$anyLabelCreated = $false

	$variationActions | ForEach-Object {
		if ($_.LocalName -eq "Label") {
			# Report progress
			Write-Progress -Activity $progressTitle -Status "Creating $($_.Label)" -PercentComplete (($variationIndex + 1) / $variationCount * 100)

			# Create the label if it doesn't already exist
			$labelTitle = $_.Title
			$item = $labelList.Items | Where-Object {$_[[Microsoft.SharePoint.SPBuiltInFieldId]::Title] -eq $labelTitle}
			#if (-not($labelList.Items | Where-Object {$_[[Microsoft.SharePoint.SPBuiltInFieldId]::Title] -eq $labelTitle})) {
			if (-not($item)){
				$item = $labelList.AddItem()
				$item["Hierarchy Is Created"] = $false
				$item[[Microsoft.SharePoint.SPBuiltInFieldId]::Title] = $labelTitle
				$item["Language"] = $_.Language
				$item["Locale"] = $_.Locale
				$item["Hierarchy Creation Mode"] = $_.CreationMode
				$item["Is Source"] = if ($_.IsSource -eq $null) { $false } else {$_.IsSource}
				$anyLabelCreated = $true
			}
			$item["Flag Control Display Name"] = $_.DisplayName
			$item["Description"] = $_.Description
			$item.Update()
		}
		$variationIndex++
	}
	# Report progress (completed)
	Write-Progress -Activity $progressTitle -Status "Completed" -Completed

	# Run VariationsCreateHierarchies timer job if needed
	if ($anyLabelCreated) {
		Log "Information" "Staring VariationsCreateHierarchies timer job to create / update hierarchies."
		$rootWeb.Site.AddWorkItem([System.Guid]::Empty, `
											[System.DateTime]::Now.ToUniversalTime(), `
											[Guid]("e7496be8-22a8-45bf-843a-d1bd83aceb25"), `
											$rootWeb.ID, $rootWeb.Site.ID, 1, $false, `
											[System.Guid]::Empty, `
											[System.Guid]::Empty, `
											$rootWeb.CurrentUser.ID, `
											$null, `
											[System.String]::Empty, `
											[System.Guid]::Empty, `
											$false) > $null
		$job = Get-SPTimerJob -Identity VariationsCreateHierarchies -WebApplication $rootWeb.Site.WebApplication
		$lastRunTime = $job.LastRunTime
		Start-SPTimerJob $job
		Log "Information" "Waiting for $($job.Title) to complete."
		Write-Host "Waitinng for VariationsCreateHierarchies job" -NoNewLine
		while ($job.LastRunTime -eq $lastRunTime) {
			Write-Host -NoNewLine .
			Start-Sleep -Seconds 2
		}
		Write-Host
		Log "Information" "$($job.Title) timer job completed."
	}
	Stop-SPAssignment -SemiGlobal $gc
}
