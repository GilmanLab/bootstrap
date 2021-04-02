<#
.Synopsis
   Downloads install files from SMB share and performs a fully silent
   installation and configuration of a ProGet server.
.DESCRIPTION
   This script is intended to be run by a machine deployed within glab that is
   desired to be configured as a ProGet server. This helper script will perform
   all of the necessary steps to fully install and configure a ProGet server
   on the local machine. The installation files should have already been
   uploaded to the given SMB path using the setup script. 
.EXAMPLE
   .\proget.ps1 -ConfigFile .\choco\config.psd1 -License mylicensekey
.NOTES
    Name: proget.ps1
    Author: Joshua Gilman (@jmgilman)
#>

# Parameters
param(
    [Parameter(
        Mandatory = $false,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 1
    )]
    [ValidateSet('ProGet', 'SQL')]
    [string]  $Install,
    [Parameter(
        Mandatory = $false,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 2
    )]
    [switch]  $Configure,
    [Parameter(
        Mandatory = $true,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 3
    )]
    [string]  $ConfigFile,
    [Parameter(
        Mandatory = $false,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 4
    )]
    [string]  $License,
    [Parameter(
        Mandatory = $false,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        Position = 5
    )]
    [string]  $ApiKey
)

function Install-SQL {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $FileFolder,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $SqlFileName,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $SqlConfigFile,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 4
        )]
        [string]  $SqlExecutable
    )
    # Unzip SQL archive
    $sql_folder = Join-Path $FileFolder 'sql'
    Expand-Archive -Path (Join-Path $FileFolder $SqlFileName) -DestinationPath $sql_folder -Force

    # Run SQL installer
    $sql_installer_path = Join-Path $sql_folder $SqlExecutable
    $proc = Start-Process $sql_installer_path -ArgumentList "/ConfigurationFile=$SqlConfigFile", '/IAcceptSQLServerLicenseTerms' -PassThru -NoNewWindow -Wait
    return $proc.ExitCode -eq 0
}

function Install-ProGet {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $FileFolder,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $ProGetFileName,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $ProGetExecutable,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 4
        )]
        [string]  $SqlInstance,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 5
        )]
        [string]  $License
    )
    # Unzip ProGet archive
    $proget_folder = Join-Path $FileFolder 'proget'
    Expand-Archive -Path (Join-Path $FileFolder $ProGetFileName) -DestinationPath $proget_folder -Force

    # Run ProGet installer
    $proget_installer_path = Join-Path $proget_folder $ProGetExecutable
    $proget_args = @('install', 
        'ProGet', 
        "--ConnectionString=`"Data Source=localhost\$SqlInstance; Integrated Security=True;`"",
        "--LicenseKey=$License")
    $proc = Start-Process $proget_installer_path -ArgumentList $proget_args -PassThru -NoNewWindow -Wait

    if ($proc.ExitCode -ne 0) {
        return $false
    }

    # Add firewall rule for ProGet web server
    New-NetFirewallRule -DisplayName 'ProGet Server' -Direction Inbound -LocalPort 8624 -Protocol TCP -Action Allow | Out-Null
    
    return $true
}

function Install-Provider {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $FileFolder,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $FileName,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $ProviderPath
    )
    New-Item -Type Directory -Path $ProviderPath -Force | Out-Null
    Expand-Archive -Path (Join-Path $FileFolder $FileName) -DestinationPath $ProviderPath -Force
}

function Install-NuGet {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $FileFolder,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $FileName,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $NuGetPath
    )
    New-Item -Type Directory -Path $NuGetPath -Force | Out-Null
    Copy-Item -Path (Join-Path $FileFolder $FileName) -Destination (Join-Path $NuGetPath $FileName) -Force
}

function Invoke-ProGetApi {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $Type,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $ApiKey,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $Endpoint,
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 4
        )]
        [object[]]  $Data
    )
    $headers = @{
        'X-ApiKey' = $ApiKey
    }
    $params = @{
        Method      = $Type
        Uri         = $Endpoint
        ContentType = 'application/json'
        Headers     = $headers
        Body        = ($Data | ConvertTo-Json)
    }
    Invoke-RestMethod @params
}

function Invoke-NuGetApi {
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [string]  $Type,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2
        )]
        [string]  $ApiKey,
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 3
        )]
        [string]  $Endpoint,
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 4
        )]
        [object[]]  $Data
    )
    $headers = @{
        'X-ApiKey' = $ApiKey
    }
    $params = @{
        Method      = $Type
        Uri         = $Endpoint
        ContentType = 'application/json'
        Headers     = $headers
        Body        = ($Data | ConvertTo-Json)
    }
    Invoke-RestMethod @params
}

# Don't let the script continue with errors
$ErrorActionPreference = 'Stop'

$CONFIG = Import-PowerShellDataFile $ConfigFile
$local_file_folder = Join-Path (Get-Location) 'files'
$sql_config_file = Join-Path $PSScriptRoot 'sql.ini'

# Check for files
if (!(Test-Path $local_file_folder)) {
    Write-Error 'Please run the download script before running this script'
    exit
}

switch ($Install) {
    'SQL' {
        # Install SQL Express
        $result = Install-SQL -FileFolder $local_file_folder -SqlFileName $CONFIG.sql.file_name -SqlConfigFile $sql_config_file -SqlExecutable $CONFIG.sql.executable
        if (!$result) {
            Write-Error 'Installation of SQL Express failed. Please check logs and try again.'
        }
        break
    }
    'ProGet' {
        # Determine SQL instance name
        [string](Get-Content -Path $sql_config_file) -match 'INSTANCENAME="(.*?)"'
        $sql_instance_name = $Matches[1]

        # Install ProGet
        $result = Install-ProGet -FileFolder $local_file_folder -ProGetFileName $CONFIG.proget.file_name -ProGetExecutable $CONFIG.proget.executable -SqlInstance $sql_instance_name -License $License
        if (!$result) {
            Write-Error 'Installation of ProGet failed. Please check the logs and try again.'
        
            # ProGet tends to leave artifacts behind, so we remove them just in case
            $proget_installer_path = Join-Path (Join-Path $local_file_folder 'proget') $ProGetExecutable
            Start-Process $proget_installer_path -ArgumentList 'uninstall', 'ProGet' -PassThru -NoNewWindow -Wait
            Exit
        }
        break
    }
}

# Make this idempotent since it has a decent chance of failing and needing to be rerun
if ($Configure) {
    # Check for API key
    if (!$PSBoundParameters.ContainsKey('ApiKey')) {
        Write-Error 'Please supply an API key to configure the ProGet server'
        exit
    }

    # Check for NuGet files
    $provider_path = Join-Path $env:ProgramFiles $CONFIG.provider.path
    $provider_full_path = Join-Path $env:ProgramFiles $CONFIG.provider.path | Join-Path -ChildPath $CONFIG.provider.name | Join-Path -ChildPath $CONFIG.provider.version
    if (!(Test-Path $provider_full_path)) {
        Install-Provider -FileFolder $local_file_folder -FileName $CONFIG.provider.file_name -ProviderPath $provider_path
    }

    $nuget_path = Join-Path $env:ProgramData $CONFIG.nuget.path
    $nuget_full_path = Join-Path $env:ProgramData $CONFIG.nuget.path | Join-Path -ChildPath $CONFIG.nuget.file_name
    if (!(Test-Path $nuget_full_path)) {
        Install-NuGet -FileFolder $local_file_folder -FileName $CONFIG.nuget.file_name -NuGetPath $nuget_path
    }

    $base_url = 'http://localhost:' + $CONFIG.proget.port + '/'
    $ps_repository_url = $base_url + 'nuget/' + $CONFIG.proget.feeds.powershell.name
    $choco_repository_url = $base_url + 'nuget/' + $CONFIG.proget.feeds.chocolatey.name
    $feeds_list_endpoint = $base_url + $CONFIG.proget.api.feeds_endpoint + 'list'
    $feeds_create_endpoint = $base_url + $CONFIG.proget.api.feeds_endpoint + 'create'
    $assets_endpoint = $base_url + 'endpoints/'

    # Check for existing feeds
    $resp = Invoke-ProGetAPI -Type 'Get' -ApiKey $ApiKey -Endpoint $feeds_list_endpoint

    # Powershell feed
    if (!($resp | Where-Object name -EQ $CONFIG.proget.feeds.powershell.name)) {
        try {
            Invoke-ProGetApi -Type 'Post' -ApiKey $ApiKey -Endpoint $feeds_create_endpoint -Data $CONFIG.proget.feeds.powershell
        }
        catch {
            Write-Error "Failed creating Powershell feed: $($Error[0])"
            exit
        }
    }

    # Chocolatey feed
    if (!($resp | Where-Object name -EQ $CONFIG.proget.feeds.chocolatey.name)) {
        try {
            Invoke-ProGetApi -Type 'Post' -ApiKey $ApiKey -Endpoint $feeds_create_endpoint -Data $CONFIG.proget.feeds.chocolatey
        }
        catch {
            Write-Error "Failed creating Chocolatey feed: $($Error[0])"
            exit
        }
    }

    # Register Powershell feed locally
    if (!(Get-PSRepository | Where-Object Name -EQ $CONFIG.proget.feeds.powershell.name)) {
        Register-PSRepository -Name $CONFIG.proget.feeds.powershell.name -SourceLocation $ps_repository_url -PublishLocation $ps_repository_url -InstallationPolicy Trusted 
    }

    # Install Chocolatey (locally)
    if (!(Get-Command choco -ErrorAction 'SilentlyContinue')) {
        # Unzip NuGet file
        $choco_nuget_path = Join-Path $local_file_folder $CONFIG.choco.file_name
        $choco_zip_path = Join-Path $local_file_folder 'choco.zip'
        $choco_folder = Join-Path $local_file_folder 'choco'
        Copy-Item $choco_nuget_path $choco_zip_path
        Expand-Archive -Path $choco_zip_path -DestinationPath $choco_folder

        # Run install file
        $installFile = Join-Path $choco_folder 'tools' | Join-Path -ChildPath 'chocolateyInstall.ps1'
        Start-Process 'powershell.exe' -ArgumentList $installFile -PassThru -NoNewWindow -Wait | Out-Null
    }

    # Publish Chocolatey NuGet
    if (!(Get-LatestNuGetPackage -FeedURL $choco_repository_url -PackageName $CONFIG.choco.package_name)) {
        $choco_nuget_path = Join-Path $local_file_folder $CONFIG.choco.file_name
        $choco_args = @(
            $choco_nuget_path,
            '-source',
            $choco_repository_url,
            '-api-key',
            $ApiKey
        )
        Start-Process 'cpush.exe' -ArgumentList $choco_args -PassThru -NoNewWindow -Wait | Out-Null
    }

    # Check for assets feed
    try {
        Invoke-Api -Type 'Get' -Endpoint ($assets_endpoint + $CONFIG.proget.feeds.bootstrap.name) -ApiKey $ApiKey
    }
    catch {
        try {
            Invoke-ProGetApi -Type 'Post' -ApiKey $ApiKey -Endpoint $feeds_create_endpoint -Data $CONFIG.proget.feeds.bootstrap
        }
        catch {
            Write-Error "Failed creating Chocolatey feed: $($Error[0])"
            exit
        }
    }
}