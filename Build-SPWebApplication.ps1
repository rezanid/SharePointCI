# Requires:
# Log.ps1
# Build-ManagedPaths.ps1
# Build-WebAppExtensions.ps1
$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
. $scriptPath\Build-ManagedPaths.ps1
. $scriptPath\Build-WebAppExtentions.ps1
. $scriptPath\Ensure-AppSettings.ps1

function Build-SPWebApplication([System.Xml.XmlElement]$Config) {
	$webapp = Get-SPWebApplication $Config.Url -ErrorAction SilentlyContinue
	$webappchanged = $false
	if ($webapp -eq $null) {
		# 1- Create application pool
		$appPool = Get-SPServiceApplicationPool $Config.ApplicationPool -ErrorAction SilentlyContinue
		$appPoolManagedAccount = Get-SPManagedAccount $Config.ApplicationPoolIdentity -ErrorAction SilentlyContinue
		if ($appPool -eq $null) {
			if (Test-Path IIS:\AppPools\$Config.ApplicationPool) {
				Log "Error" "Application pool '$($Config.ApplicationPool)' already exists."
				return
			}
			# App pool will be created automatically when calling "New-SPWebApplication":
			#else {
			#	if ($appPoolManagedAccount -eq $null) {
			#		#$appPoolManagedAccount = New-Object System.Management.Automation.PSCredential $_.ApplicationPoolAccount, (ConvertTo-SecureString $_.ApplicationPoolPassword -AsPlainText -Force)
			#		$appPoolManagedAccount  = New-SPManagedAccount -Credential $_.ApplicationPoolIdentity
			#	}
			#	$appPool = New-SPServiceApplicationPool -Name $_.ApplicationPool -Account $appPoolManagedAccount
			#}
			# In case script is stopped here:
			# Stop-Service -Name SPAdminV4
			# Start-SPAdminJob -Verbose
			# Start-Service -Name SPAdminV4
		}

		# 2- Choose the authentication mode
		if ($Config.AuthenticationMode -eq "Claims") {
			if ($Config.AuthenticationProvider -eq "Windows") {
				$auth = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -DisableKerberos
			}
			else {
				$auth = Get-SPTrustedIdentityTokenIssuer $Config.AuthenticationProvider
			}
		}

		# 3- Create the web app
		# Other possibilities when creating web app: http://blog.falchionconsulting.com/index.php/2009/12/creating-a-sharepoint-2010-site-structure-using-powershell/
		# -DatabaseServer, -DatabaseName, -Path, -AllowAnonymous, -SecureSocketsLayer
		$contentDBs = @($Config.ContentDatabases.ContentDatabase)
		$mainDb = $contentDBs[0].Name
		$webapp = New-SPWebApplication -ApplicationPool $Config.ApplicationPool `
																		-ApplicationPoolAccount $appPoolManagedAccount `
																		-Name $Config.Name `
																		-Url $Config.Url `
																		-Port $Config.Port `
																		-DatabaseName $mainDb `
																		-HostHeader $Config.HostHeader `
																		-AuthenticationProvider $auth
		Log "Information" "Web application ($($Config.Name)) has been created successfully."
	}
	if ($Config.SuperUser) {
		$webapp.Properties["portalsuperuseraccount"] = $Config.SuperUser
		$SuperUserPolicy = $webapp.Policies.Add($Config.SuperUser, "Portal Super User Account")
		$SuperUserPolicy.PolicyRoleBindings.Add($webapp.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullControl))
		$webapp.Update()
		Log "Information" "Super user ($($Config.SuperUser)) has been set successfully for the web application ($($Config.Name))."
	}
	if ($Config.SuperReader) {
		$webapp.Properties["portalsuperreaderaccount"] = $Config.SuperReader
		$SuperReaderPolicy = $webapp.Policies.Add($Config.SuperReader, "Portal Super Reader Account")
		$SuperReaderPolicy.PolicyRoleBindings.Add($webapp.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullRead))
		$webapp.Update()
		Log "Information" "Super reader ($($Config.SuperReader)) has been set successfully for the web application ($($Config.Name))."
	}

	# 4- Managed Paths
	$webapp | Build-ManagedPaths -Config $_.ManagedPaths

	# 5- Add other content DBs and Site collections if any
	$_.ContentDatabases.ContentDatabase | ForEach-Object {
		$db = Get-SPContentDatabase -Identity $_.Name -ErrorAction SilentlyContinue
		if (!$db) {
			$db = New-SPContentDatabase -Name $_.Name `
																	-WebApplication $webApp `
																	-DatabaseServer $_.Server `
																	-MaxSiteCount $_.MaxSiteCount `
																	-WarningSiteCount $_.WarningSiteCount
			Log "Information" "Content database ($($_.Name)) has been created successfully for the web application ($($webapp.Name))."
		}
		$_.SiteCollections.SiteCollection | ForEach-Object {
			$gc = Start-SPAssignment
			$site = $gc | Get-SPSite $_.Url -ErrorAction SilentlyContinue
			if (!$site) {
				$siteParams = @{
					Url = $_.Url
					OwnerAlias = $_.OwnerAccount
					ContentDatabase = $db
				}
				if ($_.Description) {	$siteParams.Add("Description", $_.Description) }
				if ($_.LCID) { $siteParams.Add("Language", $_.LCID) }
				if ($_.Name) { $siteParams.Add("Name", $_.Name) }
				if ($_.Template) { $siteParams.Add("Template", $_.Template) }
				if ($_.OwnerEmail) { $siteParams.Add("OwnerEmail", $_.OwnerEmail) }
				if ($_.SecondOwnerAccount) { $siteParams.Add("SecondaryOwnerAlias", $_.SecondOwnerAccount) }
				if ($_.SecondOwnerEmail) { $siteParams.Add("SecondaryEmail", $_.SecondOwnerEmail) }
				$site = $gc | New-SPSite @siteParams
				Log "Information" "Site collection ($($_.Name)) has been created successfully for the web application ($($Config.Name))."
			}
			Stop-SPAssignment -SemiGlobal $gc
		}
	}

	# 6- Extensions (Zones)
	$webapp | Build-WebAppExtensions -Config $_.Extensions

	# 7- Required Solutions
	$_.RequiredSolutions.Solution | ForEach-Object {
		$solution = Get-SPSolution $_.Name -ErrorAction SilentlyContinue
		if ($solution) {
			if ($solution.ContainsWebApplicationResource) {
				if (-not $solution.DeployedWebApplications.Contains($webapp)) {
					$solution | Install-SPSolution -GACDeployment:$($solution.ContainsGlobalAssembly) -CASPolicies:$($solution.ContainsCasPolicy) -WebApplication $webapp -Confirm:$false
					Block-SPDeployment $solution $true "Installing $($_.Name) to the Web Application $($webapp.Name)" 50
					Log "Information" "Prerequisite solution $($_.Name) has been installed successfully over the web application $($webapp.Name)."
				}
				else {
					Log "Information" "Prerequisite solution $($_.Name) was already installed over the web applications $($webapp.Name)."
				}
			}
			else {
				if (-not $solution.Deployed) {
					$solution | Install-SPSolution -GACDeployment:$($solution.ContainsGlobalAssembly) -CASPolicies:$($solution.ContainsCasPolicy) -AllWebApplications -Confirm:$false
					Block-SPDeployment $solution $true "Installing $name to all Web Applications" 50
					Log "Information" "Prerequisite solution $($_.Name) has been installed successfully in the farm."
				}
				else {
					Log "Information" "Prerequisite solution $($_.Name) was already installed in the farm."
				}
			}
		}
		else {
			Log "Warning" "$($_.Name) solution that is specified as a prerequisite was not found in the farm."
		}
	}

	# 8- Ensure AppSettings
	if ($_.AppSettings) {
		if ($_.AppSettings.FilePath) {
			$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
			$appSettingsFilePath = Join-Path -Path $scriptPath -ChildPath $_.AppSettings.FilePath
			$frontendAppSettings = [xml](Get-Content $appSettingsFilePath)
			$webapp | Ensure-AppSettings -Config $frontendAppSettings.configuration.appSettings
		} else {
			$webapp | Ensure-AppSettings -Config $_.SelectNodes("./add")
		}

	}
}
