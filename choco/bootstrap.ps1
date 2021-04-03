<#
.Synopsis
   Bootstraps an offline machine with Chocolatey
.DESCRIPTION
   This script is intended to be run by an offline machine deployed within glab
   and will perform the necessary steps to download and install Chocolatey to
   the machine for package management. This script expects infrastructure to
   already be in place, including:
     * A SMB share configured at $CONFIG.mount.address with a $CONFIG.mount.share share
     * A copy of the NuGet provider uploaded to {MOUNT}\$CONFIG.provider.file_name
     * A copy of the NuGet binary uploaded to {MOUNT}\$CONFIG.nuget.file_name
     * A ProGet server running at $CONFIG.proget.server
     * A Powershell feed configured at $CONFIG.proget.feeds.posh
       * The feed must have the "glab" module uploaded to it
     * A Chocolatey feed configured at $CONFIG.proget.feeds.choco
       * The feed must have the Chocolatey NuGet package uploaded to it
    This script will automatically download the NuGet provider and executable
    as needed and then download and install the Chocolatey NuGet package from
    the provided ProGet server.
    This script is intended to be uploaded to a web server and then executed
    much like the default Chocolatey install script. See the example below.
.EXAMPLE
   iex ((New-Object System.Net.WebClient).DownloadString('https://myserver.com/bootstrap.ps1'))
.NOTES
    Name: bootstrap.ps1
    Author: Joshua Gilman (@jmgilman)
#>

# Don't let the script continue with errors
$ErrorActionPreference = 'Stop'

$CONFIG = @{
    assets = @{
        feed_name   = 'bootstrap'
        provider    = 'provider.zip'
        nuget       = 'nuget.exe'
        posh_proget = 'posh-proget.zip'
    }
    proget = @{
        server = 'http://proget.gilman.io:8624'
        feeds  = @{
            powershell = @{
                name = 'internal-powershell'
                path = '/nuget/internal-powershell'
            }
            chocolatey = @{
                name = 'internal-chocolatey'
                path = '/nuget/internal-chocolatey'
            }
        }
    }
}

$PROVIDER_PATH = "$env:ProgramFiles\PackageManagement\ProviderAssemblies"
$NUGET_PATH = "$env:ProgramData\Microsoft\Windows\PowerShell\PowerShellGet"
$MIN_EXECUTION_POLICY = 'RemoteSigned'

# Check the execution policy is configured appropriately
if ((Get-ExecutionPolicy) -ne $MIN_EXECUTION_POLICY) {
    Write-Error ("The current execution policy of '$(Get-ExecutionPolicy)' " +
        "does not match the required minimum policy of '$MIN_EXECUTION_POLICY'. " +
        'Please run the following command as an administrator to update the ' + 
        'execution policy:')
    Write-Error "Set-ExecutionPolicy -ExecutionPolicy $MIN_EXECUTION_POLICY"
    Exit
}

# Ensure temp folder is present
if (!(Test-Path $env:TEMP)) {
    Write-Verbose "Creating temporary folder at $env:TEMP..."
    New-Item -Type Directory -Path $env:TEMP -Force | Out-Null
}

$url = '{0}/endpoints/{1}/content/{2}' -f ($CONFIG.proget.server, $CONFIG.assets.feed_name, $CONFIG.assets.posh_proget)
Invoke-WebRequest -Uri $url -OutFile (Join-Path $env:TEMP $CONFIG.assets.posh_proget)
Expand-Archive (Join-Path $env:TEMP $CONFIG.assets.posh_proget) $env:TEMP -Force
Import-Module (Join-Path $env:TEMP 'Posh-Proget')

$session = New-ProGetSession $CONFIG.proget.server ''
$full_provider_path = Join-Path $PROVIDER_PATH "nuget\$($CONFIG.provider.min_version)"
$full_nuget_path = Join-Path $NUGET_PATH $CONFIG.nuget.file_name

# Check for NuGet provider
if (!(Test-Path $full_provider_path)) {
    Write-Verbose 'Downloading NuGet provider...'
    Get-ProGetAsset $session $CONFIG.assets.feed_name $CONFIG.assets.provider -OutFile (Join-Path $env:TEMP $CONFIG.assets.provider)
    New-Item -Type Directory -Path $PROVIDER_PATH -Force | Out-Null
    Expand-Archive -Path (Join-Path $env:TEMP $CONFIG.assets.provider) -DestinationPath $PROVIDER_PATH -Force
}

# Check for NuGet executable
if (!(Test-Path $full_nuget_path)) {
    # Copy NuGet executable to local machine
    Write-Verbose 'Downloading NuGet executable...'
    $local_nuget_path = Join-Path $NUGET_PATH $CONFIG.assets.nuget
    New-Item -Type Directory -Path $NUGET_PATH -Force | Out-Null
    Get-ProGetAsset $session $CONFIG.assets.feed_name $CONFIG.assets.nuget -OutFile $local_nuget_path
}

# Register Powershell feed locally
if (!(Get-PSRepository | Where-Object Name -EQ $CONFIG.proget.feeds.powershell.name)) {
    $url = $CONFIG.proget.server + $CONFIG.proget.feeds.powershell.path
    Register-PSRepository -Name $CONFIG.proget.feeds.powershell.name -SourceLocation $url -PublishLocation $url -InstallationPolicy Trusted 
}

# Download Chocolatey package
$url = $CONFIG.proget.server + $CONFIG.proget.feeds.chocolatey.path
$package = Find-Package -Name 'chocolatey' -Source $url
$package | Save-Package -Path $env:TEMP -Force | Out-Null

# Rename and extract
Rename-Item -Path (Join-Path $env:TEMP $package.PackageFilename) -NewName 'choco.zip' -Force
Expand-Archive -Path (Join-Path $env:TEMP 'choco.zip') -DestinationPath (Join-Path $env:TEMP 'choco') -Force

# Install chocolatey
$installFile = Join-Path $env:TEMP 'choco/tools/chocolateyInstall.ps1'
. $installFile

# Update path
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Update sources
choco source remove -n 'chocolatey'
choco source add -n 'internal-chocolatey' -s $url