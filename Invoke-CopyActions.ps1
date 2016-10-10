# Requires:
# Log.ps1

function Build-SPWebApplication([System.Xml.XmlElement]$Config) {
	$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path

	$Config.SelectNodes("./Copy") | ForEach-Object {
		$source = [environment]::ExpandEnvironmentVariables($_.Source)
		$destination = [environment]::ExpandEnvironmentVariables($_.Destination)
		if (!(Split-Path $source -IsAbsolute)) { $source  = Join-Path $scriptPath -ChildPath $source }
		if (!(Split-Path $destination -IsAbsolute)) { $destination  = Join-Path $scriptPath -ChildPath $destination }
		if (($_.OverwriteIfExists -and [bool]::Parse($_.OverwriteIfExists)) -or ![System.IO.File]::Exists($destination)) {
			Copy-Item -Path $source -Destination $destination
		}
	}

}
