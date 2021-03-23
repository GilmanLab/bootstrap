# Don't let the script continue with errors
$ErrorActionPreference = 'Stop'

$CONFIG = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')

$cred = Get-Credential -Message 'Enter the current username and password for ESXi hosts'
$new_cred = Get-Credential -Message 'Enter the new username and password'

$CONFIG.esxi.hosts.ForEach( {
        $server = Connect-VIServer -Server $_ -Credential $cred -Force
        Set-VMHostAccount -Server $server -UserAccount root -Password $new_cred.GetNetworkCredential().Password | Out-Null
    })