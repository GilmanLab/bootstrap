@{
    esxi    = @{
        hosts = @(
            'esxi0.gilman.io',
            'esxi1.gilman.io',
            'esxi2.gilman.io',
            'esxi3.gilman.io'
        )
        ntp   = @(
            'time1.google.com',
            'time2.google.com',
            'time3.google.com'
        )
    }
    nas     = @{
        address   = 'nas.gilman.io'
        pxe_path  = '/volume1/pxe'
        tftp_path = '/volume1/tftp'
    }
    netboot = @{
        repo = 'https://github.com/netbootxyz/netboot.xyz.git'
    }
    vcenter = @{
        server     = 'vcenter.gilman.io'
        datacenter = 'Gilman'
        datastores = @(
            @{
                name    = 'Lab'
                address = 'nas.gilman.io'
                path    = '/volume1/Lab'
            }
        )
        network    = @{
            vdswitch = @{
                name        = 'Core'
                ports       = '2'
                port_groups = @(
                    @{
                        name    = 'Management'
                        vlan_id = '100'
                    },
                    @{
                        name    = 'Prod'
                        vlan_id = '101'
                    },
                    @{
                        name    = 'Dev'
                        vlan_id = '102'
                    },
                    @{
                        name    = 'Storage'
                        vlan_id = '103'
                    }
                )
            }
        }
    }
}