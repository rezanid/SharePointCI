# Requires:
# Log.ps1

function Build-WebAppExtensions {
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
		[Microsoft.SharePoint.PowerShell.SPWebApplicationPipeBind]
		$WebApplication,
		[Parameter(Position=1, Mandatory=$true)]
		[System.Xml.XmlElement]
		$Config
	)

	process {
		$webApp = $WebApplication.Read()

		$Config.SelectNodes("./*") | ForEach-Object {
			$alternateUrl = Get-SPAlternateURL -WebApplication $webApp -Zone $_.LocalName
			if (!$alternateUrl) {
				$webExtParams = @{
					Identity = $webApp
					Name = $_.Name
					Zone = $_.LocalName
				}
				if ($_.HostHeader) { $webExtParams.Add("HostHeader", $_.HostHeader) }
				if ($_.Url) { $webExtParams.Add("URL", $_.Url) }
				if ($_.Port) { $webExtParams.Add("Port", $_.Port) }
				if ($_.AnonymousAccess) { $webExtParams.Add("AllowAnonymousAccess", $_.AnonymousAccess) }
				if ($_.Path) { $webExtParams.Add("Path", $_.Path) }
				if ($_.UseSSL) { $webExtParams.Add("SecureSocketsLayer", $null) }

				# 6.1- Choose the authentication mode
				if ($_.AuthenticationMode -eq "Claims") {
					if ($_.AuthenticationProvider -eq "Windows") {
						$auth = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -DisableKerberos
					}
					else {
						$auth = Get-SPTrustedIdentityTokenIssuer $_.AuthenticationProvider
					}
					$webExtParams.Add("AuthenticationProvider", $auth)
				}
				New-SPWebApplicationExtension @webExtParams

				Log "Information" "Web application ($($webApp.Name)) has been extended successfully to $($_.Name) $($_.Url)."
			} else {
				Log "Information" "Alternate URL already exists for $($_.LocalName) zone in $($webApp.DisplayName) web application."
			}
		}
	}
}
