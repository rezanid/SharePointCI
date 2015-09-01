$snapin = {
	if ((Get-PSSnapin | ? { $_.Name -eq "Microsoft.SharePoint.PowerShell" }) -eq $null) { 
  	Add-PSSnapin Microsoft.SharePoint.PowerShell
	}
}
function global:Deploy-SPSolutions() {
  <#
  .Synopsis
    Deploys one or more Farm Solution Packages to the Farm.
  .Description
    Specify either a directory containing WSP files, a single WSP file, or an XML configuration file containing the WSP files to deploy.
    If using an XML configuration file, the format of the file must match the following:
      <Solutions>    
        <Solution Path="<full path and filename to WSP>" UpgradeExisting="false">
          <WebApplications>            
            <WebApplication>http://example.com/</WebApplication>        
          </WebApplications>    
        </Solution>
      </Solutions>
    Multiple <Solution> and <WebApplication> nodes can be added. The UpgradeExisting attribute is optional and should be specified if the WSP should be udpated and not retracted and redeployed.
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions -Identity C:\WSPs -WebApplication http://demo
    
    This example loads the function into memory and then deploys all the WSP files in the specified directory to the http://demo Web Application (if applicable).
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions -Identity C:\WSPs -WebApplication http://demo,http://mysites
    
    This example loads the function into memory and then deploys all the WSP files in the specified directory to the http://demo and http://mysites Web Applications (if applicable).
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions -Identity C:\WSPs -AllWebApplications
    
    This example loads the function into memory and then deploys all the WSP files in the specified directory to all Web Applications (if applicable).
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions -Identity C:\WSPs\MyCustomSolution.wsp -AllWebApplications
    
    This example loads the function into memory and then deploys the specified WSP to all Web Applications (if applicable).
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions -Identity C:\WSPs\MyCustomSolution.wsp -AllWebApplications -UpgradeExisting
    
    This example loads the function into memory and then deploys the specified WSP to all Web Applications (if applicable); existing deployments will be upgraded and not retracted and redeployed.
  .Example
    PS C:\> . .\Deploy-SPSolutions.ps1
    PS C:\> Deploy-SPSolutions C:\Solutions.xml
    
    This example loads the function into memory and then deploys all the WSP files specified by the Solutions.xml configuration file.
  .Parameter Config
    The XML configuration file containing the WSP files to deploy.
  .Parameter Identity
    The directory, WSP file, or XML configuration file containing the WSP files to deploy.
  .Parameter UpgradeExisting
    If specified, the WSP file(s) will be updated and not retracted and redeployed (if the WSP does not exist in the Farm then this parameter has no effect).
  .Parameter AllWebApplications
    If specified, the WSP file(s) will be deployed to all Web Applications in the Farm (if applicable).
  .Parameter WebApplication
    Specifies the Web Application(s) to deploy the WSP file to.
  .Link
    Get-Content
    Get-SPSolution
    Add-SPSolution
    Install-SPSolution
    Update-SPSolution
    Uninstall-SPSolution
    Remove-SPSolution
  #>
  [CmdletBinding(DefaultParameterSetName="FileOrDirectory")]
  param (
    [Parameter(Mandatory=$true, Position=0, ParameterSetName="Xml")]
    [ValidateNotNullOrEmpty()]
    [xml]$Config,

    [Parameter(Mandatory=$true, Position=0, ParameterSetName="FileOrDirectory")]
    [ValidateNotNullOrEmpty()]
    [string]$Identity,
    
    [Parameter(Mandatory=$false, Position=1, ParameterSetName="FileOrDirectory")]
    [switch]$UpgradeExisting,
    
    [Parameter(Mandatory=$false, Position=2, ParameterSetName="FileOrDirectory")]
    [switch]$AllWebApplications,
    
    [Parameter(Mandatory=$false, Position=3, ParameterSetName="FileOrDirectory")]
    [Microsoft.SharePoint.PowerShell.SPWebApplicationPipeBind[]]$WebApplication,
		
		[Parameter(Mandatory=$false)]
		[string]$Log,
		
		[Parameter(Mandatory=$false)]
		[switch]$Force
  )
	function Get-WebPage([string]$url)
	{
    $wc = new-object net.webclient;
    $wc.credentials = [System.Net.CredentialCache]::DefaultCredentials;
    $pageContents = $wc.DownloadString($url);
    $wc.Dispose();
    return $pageContents;
	}
  function Block-SPDeployment($solution, [bool]$deploying, [string]$status, [int]$percentComplete) {
    do { 
      Start-Sleep 2
      Write-Progress -Activity "Deploying solution $($solution.Name)" -Status $status -PercentComplete $percentComplete
      $solution = Get-SPSolution $solution
      if ($solution.LastOperationResult -like "*Failed*") { throw "An error occurred during the solution retraction, deployment, or update." }
      if (!$solution.JobExists -and (($deploying -and $solution.Deployed) -or (!$deploying -and !$solution.Deployed))) { break }
    } while ($true)
    sleep 5  
  }
  function Check-Exceptions {
    # Handle the error
    $err = $_.Exception
    Write-Output $err.Message
    while( $err.InnerException ) {
      $err = $err.InnerException
      Write-Output $err.Message
    };
    break
  }
	function Log-Error([Exception] $ex, [string]$label) {
	  $logTime = Get-Date -Format "yyyy-MM-dd hh:mm:ss.fff"
		Write-Output "$logTime [Exception] $label" | Where-Object {$Log -ne $null} | Out-File -FilePath $Log -Append
		#Write-Output $_.Exception.ToString() | Where-Object {$Log -ne $null} | Out-File $Log -Append
		Write-Output $ex.ToString() | Where-Object {$Log -ne $null} | Out-File $Log -Append
	}
	function Log([string]$level, [string]$label) {
	  $logTime = Get-Date -Format "yyyy-MM-dd hh:mm:ss.fff"
		Write-Output "$logTime [$level] $label" | Where-Object {$Log -ne $null} | Out-File -FilePath $Log -Append
	}
  function Invoke-ProvisionActions($provisionActions, [string]$progressTitle) {
    [int]$websiteCount = $provisionActions.Count
    [int]$websiteIndex = 0

		$provisionActions | ForEach-Object {
			if ($_.Name -eq "Website") {
	      # Report progress
	      Write-Progress -Activity $progressTitle -Status "Provisioning $_.Url" -PercentComplete ($websiteIndex / $websiteCount * 100)

				$website = Get-SPWeb $_.Url
				$websitechanged = $false
				if ($website -eq $null) {
	        $website = New-SPWeb $_.Url -Template $_.Template
				}
        if ($_.HasAttribute("Title") -and ($_.Title -ne $website.Title)){
          $website.Title = $_.Title
					$websitechanged = $true
				}
				if ($_.HasAttribute("Description") -and ($_.Description -ne $website.Description)) {
          $website.Description = $_.Description
					$websitechanged = $true
        }
				if ($websitechanged) {
        	$website.Update()
					$websitechanged = $false
				}
      }
      $websiteIndex++
    }
    # Report progress (completed)
	  Write-Progress -Activity $progressTitle -Status "Completed" -Completed
  }
	function Invoke-SPTimerJobActions($timerjobActions, [string]$progressTitle) {
    [int]$timerjobCount = $timerjobActions.Count
    [int]$timerjobIndex = 0

		$timerjobActions | ForEach-Object {
			if ($_.Name -eq "Start") {
	      # Report progress
	      Write-Progress -Activity $progressTitle -Status "TimerJob $_.Name on web app $_.Url" -PercentComplete ($timerjobIndex / $websiteCount * 100)

				$webapp = Get-SPWebApplication $_.Url
				$jobname = $_.JobName

				if ($webapp -eq $null) {
					$job = Get-SPTimerJob | ?{($_.Name -match $jobname) -and ($_.Parent -eq $webapp) }
	        if ($job -ne $null) {
					  #TODO: Add exception handling and implement WaitForCompletion.
						Start-SPTimerJob $job
					}
					else {
						Log "Critical" "TimerJob $_.Name was not found in $_.Url and skipped"
					}
				}				
      }
      $timerjobIndex++			
    }
    # Report progress (completed)
	  Write-Progress -Activity $progressTitle -Status "Completed" -Completed
	}
	function Invoke-IISActions($iisActions, [string]$progressTitle) {
    [int]$iisActionCount = $iisActions.Count
    [int]$iisActionIndex = 0
		
		if (-not(Get-Module "WebAdministration")) {
			if(Get-Module -ListAvailable | Where-Object { $_.name -eq "WebAdministration" }) { 
				Import-Module WebAdministration
			}
			else {
				Log "Warning" "IIS Actions are ignored since WebAdministration module is not available." 
				return 
			}
		}

		$iisActions | ForEach-Object {
			if ($_.Name -eq "Recycle") {
	      # Report progress
	      Write-Progress -Activity $progressTitle -Status "Recycling $_.AppPool" -PercentComplete ($iisActionIndex / $iisActionCount * 100)

			  #TODO: Add exception handling.
				Restart-WebAppPool $_.AppPool				
      }
			elseif ($_.Name -eq "Warmup") {
	      # Report progress
	      Write-Progress -Activity $progressTitle -Status "Warming up $_.Url" -PercentComplete ($iisActionIndex / $websiteCount * 100)

				#Invoke-WebRequest $_.Url -UseDefaultCredentials -UseBasicParsing 
				Get-WebPage $_.Url
			}
      $iisActionIndex++			
    }
    # Report progress (completed)
	  Write-Progress -Activity $progressTitle -Status "Completed" -Completed
	}
	function Invoke-SPFeatures($featureActions, [string]$progressTitle) {
    [int]$featureCount = $featureActions.Count
    [int]$featureIndex = 0
		
		$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
		#Register-PSSessionConfiguration -Name "powershell2" -Confirm:$false
		
		#Open a new session (process: wsmprovhost.exe)
		$session = New-PSSession -ConfigurationName "PS2"
		Invoke-Command -Session $session -ScriptBlock $snapin
		
		Write-Output "Waiting 10sec for debugger..."
		sleep 10
		Write-Output "Waiting finished."		
		
    $featureActions | Where-Object {($_.Name -eq "activate") -or ($_.Name -eq "deactivate") } | ForEach-Object {
      $featureIndex++
  	  [bool]$featureActivate = $_.Name -eq "activate"
      [string]$featureId = $_.Id
      [string]$featureDesc = $_.Description
      [string]$featureUrl = ""
  
      if ($featureActivate) {
        # Report progress
        Write-Progress -Activity $progressTitle -Status "Activating $featureDesc" -PercentComplete ($featureIndex / $featureCount * 100)
				try {
					# Check if there is a URL
	        if (![string]::IsNullOrEmpty($_.Url)) {
	          $featureUrl = $_.Url
			      # WebApp / Site / Web scoped feature
						Log "Information" "Activating $featureDesc ($featureId) on $featureUrl..."
						$command = {
							param($featureId, $featureUrl)
							Enable-SPFeature -Id $featureId -Url $featureUrl -Confirm:$false -PassThru -Force
						}
						Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId, $featureUrl -ErrorVariable featureErrors
	        }
	        else {
			      # Farm scoped feature
						Log "Information" "Activating $featureDesc ($featureId) on farm..."
						$command = {
							param($featureId)
							Enable-SPFeature -Id $featureId -Confirm:$false -PassThru -Force
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
        Write-Progress -Activity $progressTitle -Status "Deactivating $featureDesc" -PercentComplete ($featureIndex / $featureCount * 100)
				try {
					# Check if there is a URL
			    if (![string]::IsNullOrEmpty($_.Url)) {
	          $featureUrl = $_.Url
	          # WebApp / Site / Web scoped feature
						Log "Information" "Deactivating $featureDesc ($featureId) on $featureUrl..."
						$command = {
							param($featureId, $featureUrl)
	          	Disable-SPFeature -Id $featureId -Url $featureUrl -Confirm:$false 
						}
	          Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $featureId, $featureUrl -ErrorVariable featureErrors
						Log "Information" "Feature has been deactivated successfully."
	        }
	        else {
	          # Farm scoped feature
						Log "Information" "Dectivating $featureDesc ($featureId) on farm..."
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
	  Write-Progress -Activity $progressTitle -Status "Completed" -Completed
	}
	function Invoke-Actions($actionsRoot, [string]$progressTitle) {
		$actionsRoot.ChildNodes | Where-Object {
			($_.Name -eq "Features") -or 
			($_.Name -eq "IIS") -or 
			($_.Name -eq "TimerJobs") -or
			($_.Name -eq "Provision")} | ForEach-Object {
      if ($_.Name -eq "Provision") {
        Log "Information" "$progressTitle > Provision websites..."
        Invoke-ProvisionActions $_.ChildNodes "$progressTitle > Provisioning websites"
        Log "Information" "$progressTitle > Provision websites done."
      }	
			elseif ($_.Name -eq "Features") {
			  Log "Information" "$progressTitle > Features..."
				Invoke-SPFeatures $_.ChildNodes "$progressTitle > Features"
			  Log "Information" "$progressTitle > Features done."
			}
			elseif ($_.Name -eq "IIS") {
			  Log "Information" "$progressTitle > IIS..."
				Invoke-IISActions $_.ChildNodes "$progressTitle > Provisioning websites"
			  Log "Information" "$progressTitle > IIS done."
			}
			elseif ($_.Name -eq "TimerJobs") {
			  Log "Information" "$progressTitle > TimerJobs..."
				Invoke-SPTimerJobActions $_.ChildNodes "$progressTitle > TimerJobs"
			  Log "Information" "$progressTitle > TimerJobs done."
			}
		}	
	}

	switch ($PsCmdlet.ParameterSetName) { 
    "Xml" { 
      # An XML document was provided so (3 steps): 
      # 1- Interate through all tasks (nodes) under BeforeDeploy (only Features and Provision are supported)
			if ($Config.Deployment.BeforeDeploy -ne $null) {
				Invoke-Actions $Config.Deployment.BeforeDeploy "Predeployment"
			}

			# 2- Iterate through all the defined solutions and call the other parameter set version of the function.
			if ($Config.Deployment.Deploy.Solutions -ne $null) {
				Log "Information" "Deployment..."
	      $Config.Deployment.Deploy.Solutions.Solution | ForEach-Object {
	        [string]$path = $_.Path
	        [bool]$upgrade = $false
	        if (![string]::IsNullOrEmpty($_.UpgradeExisting)) {
	          $upgrade = [bool]::Parse($_.UpgradeExisting)
	        }
	        $webApps = $_.WebApplications.WebApplication
					$force = [boolean]$_.Force
	        Deploy-SPSolutions -Identity $path -UpgradeExisting:$upgrade -WebApplication $webApps -AllWebApplications:$(($webApps -eq $null) -or ($webApps.Length -eq 0)) -Force:$force
	      }
				Log "Information" "Deployment done."
			}
			
			# 3- Iterate through all tasks (nodes) under AfterDeploy (only Features, IIS and TimerJobs are supported)
			if ($Config.Deployment.AfterDeploy -ne $null) {
				Invoke-Actions $Config.Deployment.AfterDeploy "Postdeployment"
			}
			
      break
    }
    "FileOrDirectory" {
      $item = Get-Item (Resolve-Path $Identity)
      if ($item -is [System.IO.DirectoryInfo]) {
        # A directory was provided so iterate through all files in the directory and deploy if the file is a WSP (based on the extension)
        Get-ChildItem $item | ForEach-Object {
          if ($_.Name.ToLower().EndsWith(".wsp")) {
            Deploy-SPSolutions -Identity $_.FullName -UpgradeExisting:$UpgradeExisting -WebApplication $WebApplication
          }
        }
      } elseif ($item -is [System.IO.FileInfo]) {
        # A specific file was provided so assume that the file is a WSP if it does not have an XML extension.
        [string]$name = $item.Name
        
        if ($name.ToLower().EndsWith(".xml")) {
          Deploy-SPSolutions -Config ([xml](Get-Content $item.FullName)) -Log $Log
          return
        }
        $solution = Get-SPSolution $name -ErrorAction SilentlyContinue
        
        if ($solution -ne $null -and $UpgradeExisting) {
          # Just update the solution, don't retract and redeploy.
          Write-Progress -Activity "Deploying solution $name" -Status "Updating $name" -PercentComplete -1
          $solution | Update-SPSolution -CASPolicies:$($solution.ContainsCasPolicy) `
            -GACDeployment:$($solution.ContainsGlobalAssembly) `
            -LiteralPath $item.FullName
        
          Block-SPDeployment $solution $true "Updating $name" -1
          Write-Progress -Activity "Deploying solution $name" -Status "Updated" -Completed
          
          return
        }

        if ($solution -ne $null) {
          #Retract the solution
          if ($solution.Deployed) {
            Write-Progress -Activity "Deploying solution $name" -Status "Retracting $name" -PercentComplete 0
            if ($solution.ContainsWebApplicationResource) {
              $solution | Uninstall-SPSolution -AllWebApplications -Confirm:$false
            } else {
              $solution | Uninstall-SPSolution -Confirm:$false
            }
            #Block until we're sure the solution is no longer deployed.
            Block-SPDeployment $solution $false "Retracting $name" 12
            Write-Progress -Activity "Deploying solution $name" -Status "Solution retracted" -PercentComplete 25
          }

          #Delete the solution
          Write-Progress -Activity "Deploying solution $name" -Status "Removing $name" -PercentComplete 30
          Get-SPSolution $name | Remove-SPSolution -Confirm:$false
          Write-Progress -Activity "Deploying solution $name" -Status "Solution removed" -PercentComplete 50
        }

        #Add the solution
        Write-Progress -Activity "Deploying solution $name" -Status "Adding $name" -PercentComplete 50
        $solution = Add-SPSolution $item.FullName
        Write-Progress -Activity "Deploying solution $name" -Status "Solution added" -PercentComplete 75

        #Deploy the solution
        if (!$solution.ContainsWebApplicationResource) {
          Write-Progress -Activity "Deploying solution $name" -Status "Installing $name" -PercentComplete 75
          $solution | Install-SPSolution -GACDeployment:$($solution.ContainsGlobalAssembly) -CASPolicies:$($solution.ContainsCasPolicy) -Confirm:$false
          Block-SPDeployment $solution $true "Installing $name" 85
        } else {
          if ($WebApplication -eq $null -or $WebApplication.Length -eq 0) {
            Write-Progress -Activity "Deploying solution $name" -Status "Installing $name to all Web Applications" -PercentComplete 75
            $solution | Install-SPSolution -GACDeployment:$($solution.ContainsGlobalAssembly) -CASPolicies:$($solution.ContainsCasPolicy) -AllWebApplications -Confirm:$false -Force:$Force
            Block-SPDeployment $solution $true "Installing $name to all Web Applications" 85
          } else {
            $WebApplication | ForEach-Object {
              $webApp = $_.Read()
              Write-Progress -Activity "Deploying solution $name" -Status "Installing $name to $($webApp.Url)" -PercentComplete 75
              $solution | Install-SPSolution -GACDeployment:$gac -CASPolicies:$cas -WebApplication $webApp -Confirm:$false -Force:$Force
              Block-SPDeployment $solution $true "Installing $name to $($webApp.Url)" 85
            }
          }
        }
        Write-Progress -Activity "Deploying solution $name" -Status "Deployed" -Completed
      }
      break 
    }
  } 
}
