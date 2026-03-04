variable "compartment_id" {
  description = "OCI Compartment OCID"
  type        = string
  default     = "ocid1.tenancy.oc1..aaaaaaaa7jmtb7jlx2jgi2otqpe2fmwfjlknbjwutptykj4rvncqz3cl2nna"
}

variable "image_id" {
  description = "OCI Image OCID for the instance"
  type        = string
  default     = "ocid1.image.oc1.ap-mumbai-1.aaaaaaaa4jz7qhwqpirw4xjrqtiygajvqtpt3x2iigwhi7szxv3aizhvrz2a"
}

variable "subnet_id" {
  description = "OCI Subnet OCID"
  type        = string
  default     = "ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaa767k4dojbyxavhpmtoy5jy4cbmdwavv4gzv4alkk66ee4oeg3fiq"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
