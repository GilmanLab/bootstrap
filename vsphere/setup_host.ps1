# Don't let the script continue with errors
$ErrorActionPreference = 'Stop'

$CONFIG = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')

$cred = Get-Credential -Message 'Enter the current username and password for ESXi hosts'
$new_cred = Get-Credential -Message 'Enter the new username and password'

$CONFIG.esxi.hosts.ForEach( {
        $server = Connect-VIServer -Server $_ -Credential $cred -Force
        $vmhost = Get-VMHost | Where-Object Name -EQ $_

        # Change password
        Set-VMHostAccount -Server $server -UserAccount root -Password $new_cred.GetNetworkCredential().Password | Out-Null

        # Configure NTP
        $vmhost | Add-VMHostNtpServer -NtpServer $CONFIG.esxi.ntp | Out-Null
        $vmhost | Get-VMHostService | Where-Object Key -EQ 'ntpd' | Start-VMHostService | Out-Null
        $vmhost | Get-VMHostService | Where-Object Key -EQ 'ntpd' | Set-VMHostService -Policy 'automatic' | Out-Null
    })