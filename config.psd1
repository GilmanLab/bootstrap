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
}