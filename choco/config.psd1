@{
    choco       = @{
        package_name = 'chocolatey'
        url          = 'https://www.nuget.org/api/v2/package/chocolatey/0.10.14'
        file_name    = 'chocolatey.0.10.14.nupkg'
    }
    nuget       = @{
        url       = 'https://aka.ms/psget-nugetexe'
        file_name = 'nuget.exe'
        path      = 'Microsoft\Windows\PowerShell\PowerShellGet'
    }
    posh_proget = @{
        name = 'Posh-ProGet'
    }
    proget      = @{
        server     = 'http://proget.gilman.io'
        port       = '8624'
        file_name  = 'proget.zip'
        executable = 'hub.exe'
        feeds      = @{
            bootstrap  = @{ 
                name        = 'bootstrap'
                feedType    = 'asset'
                description = 'Chocolatey bootstrap files'
                active      = $true
            }
            chocolatey = @{
                name        = 'internal-chocolatey'
                feedType    = 'chocolatey'
                description = 'Internal Chocolatey feed for hosting programs'
                active      = $true
            }
            powershell = @{
                name        = 'internal-powershell'
                feedType    = 'powershell'
                description = 'Internal Powershell feed for hosting modules'
                active      = $true
            }
        }
        api        = @{
            feeds_endpoint = '/api/management/feeds/'
        }
    }
    provider    = @{
        name      = 'nuget'
        file_name = 'provider.zip'
        version   = '2.8.5.201'
        path      = 'PackageManagement\ProviderAssemblies'
    }
    sql         = @{
        file_name  = 'sql.zip'
        executable = 'SETUP.EXE'
    }
}