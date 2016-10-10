function Log-Error([Exception] $ex, [string]$label) {
	$logTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
	$mtx = New-Object System.Threading.Mutex($false, "TestMutex")
	if ($mtx.WaitOne(1000)) {
		if (!$LogFilePath) {
			$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
			$LogFilePath = Join-Path -Path $scriptPath -ChildPath Install.log
		}
		Write-Output "$logTime [Exception] $label" | Where-Object {$LogFilePath -ne $null} | Out-File -FilePath $LogFilePath -Append
		Write-Output "    $ex" | Where-Object {$LogFilePath -ne $null} | Out-File $LogFilePath -Append
	} else {
		Write-Host "Log file is locked!"
		Write-Host "$logTime [Exception] $label"
		Write-Host "    $ex"
	}
	$mtx.ReleaseMutex()
}

function Log([string]$level, [string]$label) {
	$logTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
	$mtx = New-Object System.Threading.Mutex($false, "TestMutex")
	if ($mtx.WaitOne(1000)) {
		if (!$LogFilePath) {
			$scriptPath = Split-Path -Parent $script:MyInvocation.MyCommand.Path
			$LogFilePath = Join-Path -Path $scriptPath -ChildPath Install.log
		}
		Write-Output "$logTime [$level] $label" | Where-Object {$LogFilePath -ne $null} | Out-File -FilePath $LogFilePath -Append
		Write-Host "$logTime [$level] $label"
	} else {
		Write-Host "Log file is locked!"
		Write-Host "$logTime [$level] $label"
	}
	$mtx.ReleaseMutex()
}
