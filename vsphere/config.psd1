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
        iscsi     = 'iqn.2000-01.com.synology:GILMAN-DSM1.Target-1.9d17da5224'
    }
    netboot = @{
        repo = 'https://github.com/netbootxyz/netboot.xyz.git'
    }
    vcenter = @{
        server     = 'vcenter.gilman.io'
        datacenter = 'Gilman'
        cluster    = @{
            name = 'Lab'
            evc  = 'intel-haswell'
        }
        datastores = @(
            @{
                name    = 'Lab'
                address = 'nas.gilman.io'
                path    = '/volume2/Lab'
            }
        )
        iscsi      = @{
            name = 'iSCSI'
            host = 'esxi0.gilman.io'
        }
        network    = @{
            vmk      = @{
                storage = @(
                    @{
                        host       = 'esxi0.gilman.io'
                        address    = '192.168.3.20'
                        subnet     = '255.255.255.0'
                        gateway    = '192.168.3.1'
                        port_group = 'Storage'
                    }
                    @{
                        host       = 'esxi1.gilman.io'
                        address    = '192.168.3.21'
                        subnet     = '255.255.255.0'
                        gateway    = '192.168.3.1'
                        port_group = 'Storage'
                    }
                    @{
                        host       = 'esxi2.gilman.io'
                        address    = '192.168.3.22'
                        subnet     = '255.255.255.0'
                        gateway    = '192.168.3.1'
                        port_group = 'Storage'
                    }
                    @{
                        host       = 'esxi3.gilman.io'
                        address    = '192.168.3.23'
                        subnet     = '255.255.255.0'
                        gateway    = '192.168.3.1'
                        port_group = 'Storage'
                    }
                )
            }
            vdswitch = @{
                name            = 'Core'
                ports           = '2'
                management_name = 'Management'
                port_groups     = @(
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