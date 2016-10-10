function Get-WebPage([string]$url) {
	$wc = new-object net.webclient;
	$wc.credentials = [System.Net.CredentialCache]::DefaultCredentials;
	$pageContents = $wc.DownloadString($url);
	$wc.Dispose();
	return $pageContents;
}
