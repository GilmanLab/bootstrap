variable "vsphere_username" {
  type    = string
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

source "vsphere-iso" "ws2016core" {
  vcenter_server      = "vcenter.gilman.io"
  username            = "${var.vsphere_username}"
  password            = "${var.vsphere_password}"
  insecure_connection = true

  boot_command = [
        "a<enter><wait>a<enter><wait>a<enter><wait>a<enter>"
      ]
  boot_wait = "-1s"

  datacenter = "Gilman"
  cluster    = "Lab"
  datastore  = "iSCSI"

  convert_to_template = true

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = "GlabT3mp!"

  vm_name = "WS2016Core"
  CPUs    = 2
  RAM     = 4096
  firmware = "efi"

  guest_os_type = "windows9Server64Guest"

  disk_controller_type = ["lsilogic-sas"]
  storage {
    disk_size             = 40960
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = "Dev"
    network_card = "vmxnet3"
  }

  iso_paths = [
    "[Lab] iso/en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso",
    "[] /vmimages/tools-isoimages/windows.iso"
  ]

  floppy_files = [
    "autounattend.xml",
    "install-vm-tools.ps1",
    "enable-winrm.ps1"
  ]
}

build {
  sources = ["source.vsphere-iso.ws2016core"]

}