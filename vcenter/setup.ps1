<#
.Synopsis
   Bootstraps the glab vCenter server with common settings
.DESCRIPTION
   This script is intended to be run by a machine deployed within glab and is
   used to bootstrap a newly installed vCenter server. 
.EXAMPLE
   .\setup.ps1 -Server vcenter.gilman.io
.NOTES
    Name: set_dns.ps1 -ConfigFile .\config.psd1
    Author: Joshua Gilman (@jmgilman)
#>

# Parameters
param(
    [Parameter(
        Mandatory = $true,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 1
    )]
    [string]  $ConfigFile
)

$CONFIG = Import-PowerShellDataFile $ConfigFile

if (!($global:DefaultVIServer | Where-Object Name -EQ $CONFIG.vcenter.server | Select-Object -ExpandProperty IsConnected)) {
    Connect-VIServer -Server $CONFIG.vcenter.server -Force
}

$vcenter = $global:DefaultVIServer | Where-Object Name -EQ $CONFIG.vcenter.server

# Create datacenter
if (!(Get-Datacenter | Where-Object Name -EQ $CONFIG.vcenter.datacenter)) {
    New-Datacenter -Name $CONFIG.vcenter.datacenter -Location (Get-Folder)
}

$dc = Get-Datacenter | Where-Object Name -EQ $CONFIG.vcenter.datacenter

# Create VD Switch
$network = $CONFIG.vcenter.network
if (!(Get-VDSwitch | Where-Object Name -EQ $network.vdswitch.name)) {
    New-VDSwitch -Name $network.vdswitch.name -Location $dc -NumUplinkPorts $network.vdswitch.ports
}

$switch = Get-VDSwitch | Where-Object Name -EQ $network.vdswitch.name

# Create port groups
foreach ($pg in $network.vdswitch.port_groups) {
    if (!(Get-VDPortgroup | Where-Object Name -EQ $pg.name)) {
        New-VDPortgroup -VDSwitch $switch -Name $pg.name -VlanId $pg.vlan_id
    }
}

# Add licenses
$lm = Get-View($vcenter.ExtensionData.content.LicenseManager)
$lam = Get-View($lm.licenseAssignmentManager)

if (!($lm.Licenses | Where-Object EditionKey -EQ 'vc.standard.instance')) {
    $key = Read-Host 'Enter vCenter license key: '
    $lm.AddLicense($key, $null)
    $lam.UpdateAssignedLicense($vcenter.InstanceUuid, $key, $null)
}

if (!($lm.Licenses | Where-Object EditionKey -EQ 'esx.enterprisePlus.cpuPackageCoreLimited')) {
    $key = Read-Host 'Enter ESXi license key: '
    $lm.AddLicense($key, $null)
}

if (!($lm.Licenses | Where-Object EditionKey -EQ 'vsan.enterprise.cpuPackageCoreLimited')) {
    $key = Read-Host 'Enter vSAN license key: '
    $lm.AddLicense($key, $null)
}

# Add ESXi hosts
$hosts = Get-VMHost

foreach ($esxi_host in $CONFIG.esxi.hosts) {
    if (!($hosts | Where-Object Name -EQ $esxi_host)) {
        if (!$esxi_cred) {
            $esxi_cred = Get-Credential -Message 'Enter credentials for ESXi hosts'
        }
        Add-VMHost -Name $esxi_host -Location $dc -Credential $esxi_cred -Force
    }
}

# License ESXi hosts
$esxi_hosts = Get-VMHost
$esxi_key = $lm.Licenses | Where-Object EditionKey -EQ 'esx.enterprisePlus.cpuPackageCoreLimited'
foreach ($esxi_host in $CONFIG.esxi.hosts) {
    $esxi_host = $esxi_hosts | Where-Object name -EQ $esxi_host
    $cur_key = $esxi_host | Select-Object LicenseKey
    if ($cur_key.LicenseKey -eq '00000-00000-00000-00000-00000') {
        Set-VMHost -VMHost $esxi_host -LicenseKey $esxi_key.LicenseKey
    }
}

# Add datastores
$datastores = Get-Datastore
foreach ($ds in $CONFIG.vcenter.datastores) {
    if (!($datastores | Where-Object Name -EQ $ds.name)) {
        $esxi_hosts | New-Datastore -Name $ds.name -NfsHost $ds.address -Path $ds.path
    }
}

# Disable console and SSH access
Get-VMHost | Get-VMHostService | Where-Object { ($_.Key -EQ 'TSM') -and ($_.Running -EQ $True) } | Stop-VMHostService -Confirm:$false
Get-VMHost | Get-VMHostService | Where-Object { ($_.Key -EQ 'TSM-SSH') -and ($_.Running -EQ $True) } | Stop-VMHostService -Confirm:$false

# Suppress warnings
Get-VMHost | Get-AdvancedSetting -Name 'UserVars.SuppressCoredumpWarning' | Where-Object Value -EQ 0 | Set-AdvancedSetting -Value 1 -Confirm:$false
Get-VMHost | Get-AdvancedSetting -Name 'UserVars.SuppressHyperthreadWarning' | Where-Object Value -EQ 0 | Set-AdvancedSetting -Value 1 -Confirm:$false

# Set log location
$settings = Get-VMHost | Get-AdvancedSetting | Where-Object { ($_.Name -eq 'Syslog.global.logDir') -and ($_.Value -eq '[] /scratch/log') }
foreach ($setting in $settings) {
    $short_name = $setting.Entity -replace '.gilman.io', ''
    $setting | Set-AdvancedSetting -Value "[Lab] logs/$short_name" -Confirm:$false
}