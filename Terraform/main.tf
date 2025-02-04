# DeepSeek Generated Terraform file, not tested.

terraform {
  required_providers {
    cudo = {
      source = "cudo/cudo"
      version = "~> 1.0"
    }
  }
}

provider "cudo" {
  api_key = var.cudo_api_key
}

# Data Server (Linux)
resource "cudo_compute_vm" "data_server" {
  id             = "data-server"
  memory_gib     = 8
  vcpus          = 4
  boot_disk {
    image_id     = "ubuntu-22-04"
    size_gib     = 30
  }
  data_disks {
    image_id     = "blank"
    size_gib     = 500
  }
  machine_type   = "standard"
  region_id      = var.region
  ssh_key_source = "project"
  
  network_config {
    external_ip  = true
    forwarded_ports = [
      {
        port          = 443
        host_port     = 443
        protocol      = "tcp"
      },
      {
        port          = 445
        host_port     = 445
        protocol      = "tcp"
      }
    ]
  }
  
  metadata = {
    user-data = base64encode(file("data-server.sh"))
  }
}

# Render Server (Windows with GPU)
resource "cudo_compute_vm" "render_server" {
  id             = "render-server"
  memory_gib     = 128
  vcpus          = 32
  boot_disk {
    image_id     = var.windows_image_id
    size_gib     = 200
  }
  machine_type   = "gpu"
  gpu_model      = "a4000"  # Choose appropriate GPU model
  region_id      = var.region
  ssh_key_source = "project"
  
  network_config {
    external_ip  = false
    forwarded_ports = [
      {
        port          = 3389
        host_port     = 3389
        protocol      = "tcp"
      }
    ]
  }
  
  metadata = {
    samba-mount = <<-EOT
      net use Z: \\${cudo_compute_vm.data_server.ip_address}\RUSHES /user:${var.samba_username} ${var.samba_password} /persistent:yes
    EOT
  }
  
  depends_on = [cudo_compute_vm.data_server]
}

# Variables
variable "cudo_api_key" {
  description = "Cudo API key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Cudo region ID"
  default     = "eu-west-1"
}

variable "windows_image_id" {
  description = "Pre-configured Windows image ID with DaVinci Resolve"
  type        = string
}

variable "samba_username" {
  description = "Samba share username"
  default     = "davinci"
}

variable "samba_password" {
  description = "Samba share password"
  type        = string
  sensitive   = true
}

# Outputs
output "data_server_ip" {
  value = cudo_compute_vm.data_server.ip_address
}

output "render_server_ip" {
  value = cudo_compute_vm.render_server.ip_address
}
