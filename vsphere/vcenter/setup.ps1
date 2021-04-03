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

# Migrate networking
$switch = Get-VDSwitch | Where-Object Name -EQ $CONFIG.vcenter.network.vdswitch.name
foreach ($vmhost in Get-VMHost) {
    if (!($vmhost | Get-VDSwitch)) {
        # Refuse to migrate if the host has VM's
        if (($vmhost | Get-VM).Count -gt 0) {
            Write-Warning "Skipping host $($vmhost.Name) as it has VM's on it..."
            continue
        }

        # Since this is potentially dangerous, we just ask for confirmation
        $confirmation = Read-Host "Migrate the networking for $($vmhost.Name)? [y/n]"
        if ($confirmation -ne 'y') {
            continue
        }

        # Add host to switch
        $switch | Add-VDSwitchVMHost -VMHost $vmhost

        $vmnic0 = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic0
        $vmnic1 = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
        $vmk = Get-VMHostNetworkAdapter -Name vmk0 -VMHost $vmhost
        $vdpg = Get-VDPortgroup -Name $CONFIG.vcenter.network.vdswitch.management_name -VDSwitch $switch

        # Move first uplink
        $switch | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmnic0 -Confirm:$false
        Start-Sleep -Seconds 2

        # Move adapter
        Set-VMHostNetworkAdapter -PortGroup $vdpg -VirtualNic $vmk -Confirm:$false
        Start-Sleep -Seconds 5

        # Move second uplink
        $switch | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmnic1 -Confirm:$false
    }
}

# Add storage VMK's
foreach ($vmk in $CONFIG.vcenter.network.vmk.storage) {
    $vmhost = Get-VMHost | Where-Object Name -EQ $vmk.host

    # Skip hosts not added to the VD Switch
    if (!($vmhost | Get-VDSwitch)) {
        continue
    }
    
    if (!(($vmhost | Get-VMHostNetworkAdapter | Select-Object -ExpandProperty IP) -contains $vmk.address)) {
        # Create VMKernel
        $vmhost | New-VMHostNetworkAdapter -PortGroup $vmk.port_group -VirtualSwitch $switch -IP $vmk.address -SubnetMask $vmk.subnet -VsanTrafficEnabled $True -VMotionEnabled $True
        Start-Sleep -Seconds 5

        # Override gateway
        $netMgr = Get-View ($vmhost | Get-View).ConfigManager.NetworkSystem
        $iproute = New-Object VMware.Vim.HostIpRouteConfig
        $iproute.defaultGateway = $vmk.gateway
        $netMgr.UpdateIpRouteConfig($iproute)
    }
}

# Configure iSCSI
foreach ($vmhost in Get-VMHost) {
    if (!($vmhost | Get-VMHostStorage | Select-Object -ExpandProperty SoftwareIScsiEnabled)) {
        # Enable software adapter
        $vmhost | Get-VMHostStorage | Set-VMHostStorage -SoftwareIScsiEnabled $True
        Start-Sleep -Seconds 5

        # Add target
        $adapter = $vmhost | Get-VMHostHba -Type iScsi | Where-Object Model -EQ 'iSCSI Software Adapter'
        $adapter | New-IScsiHbaTarget -Address $CONFIG.nas.address -IScsiName $CONFIG.nas.iscsi -Type Static

        # Rescan HBA's
        $vmhost | Get-VMHostStorage -RescanAllHba
    }
}

# Create iSCSI datastore
if (!(Get-Datastore | Where-Object Name -EQ $CONFIG.vcenter.iscsi.name)) {
    $iscsi_host = Get-VMHost | Where-Object Name -EQ $CONFIG.vcenter.iscsi.host
    $device = $iscsi_host | Get-ScsiLun | Where-Object Model -EQ 'iSCSI Storage'
    $iscsi_host | New-Datastore -Name $CONFIG.vcenter.iscsi.name -Path ($device | Select-Object -ExpandProperty CanonicalName)
}

# Create cluster
if (!(Get-Cluster | Where-Object Name -EQ $CONFIG.vcenter.cluster.name)) {
    $dc | New-Cluster -Name $CONFIG.vcenter.cluster.name -EVCMode $CONFIG.vcenter.cluster.evc
}