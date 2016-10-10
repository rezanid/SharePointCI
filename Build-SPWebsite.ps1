# Requires:
# Log.ps1

function Build-SPWebsite([System.Xml.XmlElement]$Config) {
	$website = Get-SPWeb $Config.Url -ErrorAction SilentlyContinue
	$websitechanged = $false
	if ($website -eq $null) {
		$website = New-SPWeb $Config.Url -Template $Config.Template
		Log "Information" "New website (URL: $($Config.Url) Template: $($Config.Template)) has been created successfully"
	} else {
		Log "Information" "Website (URL: $($Config.Url) already exists."
	}
	if ($Config.HasAttribute("Title") -and ($Config.Title -ne $website.Title)) {
		$website.Title = $Config.Title
		$websitechanged = $true
	}
	if ($Config.HasAttribute("Description") -and ($Config.Description -ne $website.Description)) {
		$website.Description = $Config.Description
		$websitechanged = $true
	}
	if ($websitechanged) {
		$website.Update()
		$websitechanged = $false
		Log "Information" "Website (URL: $($Config.Url)) has been updated successfully"
	}
}
