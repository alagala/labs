variable "project_location" {
  default = "southeastasia"
}

variable "res_group_name" {
  default = "adf-durable-rg"
}

variable "vnet_address_space" {
  default = "10.11.128.0/24"
}

variable "functions_subnet_prefix" {
  default = "10.11.128.0/26"
}

variable "adf_ir_subnet_prefix" {
  default = "10.11.128.64/27"
}

variable "bastion_subnet_prefix" {
  default = "10.11.128.224/27"
}

variable "dev_vm_username" {
  default = "testadmin"
}

variable "dev_vm_password" {
  default = "Password1234!"
}

variable "storage_container" {
  default = "demo"
}