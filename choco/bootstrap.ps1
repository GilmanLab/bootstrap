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

# Modify the values below before uploading
$CONFIG = @{
    choco    = @{
        package_name = 'chocolatey'
    }
    mount    = @{
        address = '\\nas.gilman.io'
        share   = 'Software'
    }
    nuget    = @{
        file_name = 'nuget.exe'
    }
    proget   = @{
        server = 'http://proget.gilman.io:8624'
        feeds  = @{
            posh  = 'internal-powershell'
            choco = 'internal-chocolatey'
        }
    }
    provider = @{
        file_name   = 'nuget.zip'
        min_version = '2.8.5.201'
    }
}

# Do not edit
$DRIVE_NAME = 'BOOTSTRAP'
$DRIVE_PATH = $DRIVE_NAME + ':\'
$PROVIDER_PATH = "$env:ProgramFiles\PackageManagement\ProviderAssemblies"
$NUGET_PATH = "$env:ProgramData\Microsoft\Windows\PowerShell\PowerShellGet"
$GLAB_MODULE = 'glab'
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

# Check if we need to mount SMB share
$full_provider_path = Join-Path $PROVIDER_PATH "nuget\$($CONFIG.provider.min_version)"
$full_nuget_path = Join-Path $NUGET_PATH $CONFIG.nuget.file_name
if (!(Test-Path $full_provider_path) -or !(Test-Path $full_nuget_path)) {
    # Need the user credentials to attach to the SMB share
    $cred = Get-Credential -Message "Enter credentials to connect to $($CONFIG.mount.address)"
    $mount_path = Join-Path -Path $CONFIG.mount.address -ChildPath $CONFIG.mount.share
    New-PSDrive -Name $DRIVE_NAME -PSProvider 'FileSystem' -Root $mount_path -Credential $cred | Out-Null
}

# Check for NuGet provider
if (!(Test-Path $full_provider_path)) {
    Write-Verbose 'Downloading NuGet provider...'
    $archive_path = Join-Path -Path $DRIVE_PATH -ChildPath $CONFIG.provider.file_name
    New-Item -Type Directory -Path $PROVIDER_PATH -Force | Out-Null
    Expand-Archive -Path $archive_path -DestinationPath $PROVIDER_PATH -Force
}

# Check for NuGet executable
if (!(Test-Path $full_nuget_path)) {
    # Copy NuGet executable to local machine
    Write-Verbose 'Downloading NuGet executable...'
    $remote_nuget_path = Join-Path -Path $DRIVE_PATH -ChildPath $CONFIG.nuget.file_name
    $local_nuget_path = Join-Path $NUGET_PATH $CONFIG.nuget.file_name
    New-Item -Type Directory -Path $NUGET_PATH -Force | Out-Null
    Copy-Item -Path $remote_nuget_path -Destination $local_nuget_path
}

# Check for internal Powershell repository
if (!(Get-PSRepository | Where-Object Name -EQ $CONFIG.proget.feeds.posh)) {
    # Import the newly copied provider
    Write-Verbose 'Importing provider...'
    Import-PackageProvider -Name NuGet -RequiredVersion $CONFIG.provider.min_version | Out-Null

    # Register local repository as trusted
    Write-Verbose 'Registering local Powershell repository...'
    $url = ($CONFIG.proget.server, 'nuget', $CONFIG.proget.feeds.posh) -join '/'
    Register-PSRepository -Name $CONFIG.proget.feeds.posh -SourceLocation $url -InstallationPolicy Trusted 
}

# Check for glab module
if (!(Get-InstalledModule | Where-Object Name -EQ $GLAB_MODULE)) {
    Write-Verbose 'Downloading glab module...'
    Install-Module -Name $GLAB_MODULE -Repository $CONFIG.proget.feeds.posh 
}

# Import module
Import-Module -Name $GLAB_MODULE

# Get the download URL for the Chocolatey NuGet package
Write-Verbose 'Getting chocolatey URL...'
$chocoFeedURL = ($CONFIG.proget.server, 'nuget', $CONFIG.proget.feeds.choco) -join '/'
$chocoDownloadURL = Get-LatestNuGetPackage -FeedURL $chocoFeedURL -PackageName $CONFIG.choco.package_name

# Install Chocolatey
Write-Verbose 'Installing Chocolatey...'
Install-Chocolatey -NuGetURL $chocoDownloadURL -TempFolder $(New-TempFolder) | Out-Null