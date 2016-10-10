# Requires:
# Log.ps1

function Provision-SPListItems([System.Xml.XmlElement]$Config, [string]$ProgressTitle) {
	#[array]$listItems = $Config.ChildNodes | Where-Object { $_.Name -eq "ListItem" }
	$listItems = $Config.SelectNodes("./ListItem")
	[int]$listItemCount = $listItems.Count
	[int]$listItemSuccessCount = 0
	[int]$listItemIndex = 0

	# Report progress
	Write-Progress -Activity $ProgressTitle -Status "list: $Config.Title" -PercentComplete ($listItemIndex / $listItemCount * 100)

	$web = Get-SPWeb $Config.Web
	$list = $web.Lists | Where-Object { $_.Title -eq $Config.List }

	if (!$list) {
		Log "Error" "No list was found in $($Config.Web) with the title '$($Config.List)'"
		# Report progress (completed)
		Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed
		return
	}

	$listItems | ForEach-Object {
		if ($_.LocalName -eq "ListItem") {
			try {
				Provision-SPListItem $_ $list
				$listItemSuccessCount++
			} catch [Exception] {
				Log-Error $_.Exception "An exception has been thrown while provisioning item #$listItemCount in $($Config.List) list. Please check the following logs for more details."
			}
			# Report progress
			Write-Progress -Activity $ProgressTitle -Status "Provisioning items" -PercentComplete (($listItemIndex + 1) / $listItemCount * 100)
		}
		$listItemIndex++
	}
	# Report progress (completed)
	Write-Progress -Activity $ProgressTitle -Status "Completed" -Completed

	Log "Information" "$listItemSuccessCount out of $listItemCount list items has been provisioned successfully in $($Config.List) list."
}

function Provision-SPListItem([System.Xml.XmlElement]$itemConfig, [Microsoft.SharePoint.SPList]$list) {
	# Find or create a new list item
	if ($itemConfig.MatchColumn) {
		$matchCol = $itemConfig.MatchColumn
		$matchVal = $itemConfig.MatchValue
		$listitem = $list.Items | Where { $_[$matchCol] -eq $matchVal }
	}
	if (!$listitem) { $listitem = $list.AddItem() }
	# Fill in the fields (based on the attributes)
	$itemConfig.Attributes |
		Where-Object { $_.LocalName -ne "MatchColumn" -and $_.LocalName -ne "MatchValue" } |
			ForEach-Object {
				$listitem[$_.LocalName] = Get-ColumnValue $_
			}
	# Fill in the fields (based on <Column> elements under <Item>)
	if ($itemConfig.Column) { $itemConfig.Column |
		ForEach-Object {
			$listitem[$_.Title] = Get-ColumnValue $_
		}
	}
	# Update the item
	$listitem.Update()
}

function Get-ColumnValue (
	[Parameter(Position=0, ParameterSetName="Element")]  [System.Xml.XmlElement]$colElement,
	[Parameter(Position=0, ParameterSetName="Attribute")]  [System.Xml.XmlAttribute]$colAttribute
) {
	if ($colAttribute) { return $colAttribute.Value }
		#$colTitle = $colAttribute.Name
		#$colValue = $colAttribute.Value
	#}
	elseif($colElement) {
		$colTitle = $colElement.Title
		if ($colElement.FilePath) {
			$filePath = $colElement.FilePath
			if (![System.IO.Path]::IsPathRooted($filePath)) {
				$filePath = Join-Path (Split-Path -Parent $script:MyInvocation.MyCommand.Path) $filePath
			}
			# In PS 3.0 it is possible to use Get-Content -Raw
			#return Get-Content $filePath | Out-String
			return [System.IO.File]::ReadAllText($filePath)
			#$colValue = Get-Content $filePath
		}
		else {
			return $colElement.Value
			#$colValue = $colElement.Value
		}
	}
}
