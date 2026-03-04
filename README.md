# OCI Compute Instance - Terraform

Terraform configuration to launch an Oracle Cloud Infrastructure compute instance (A1 Flex shape).

## Prerequisites

- OCI CLI configured (`~/.oci/config`)
- Terraform >= 1.0

## Usage

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values

3. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| compartment_id | OCI Compartment OCID | - |
| image_id | OCI Image OCID | Oracle Linux 8 (Mumbai) |
| subnet_id | OCI Subnet OCID | - |
| ssh_public_key_path | Path to SSH public key | `~/.ssh/id_ed25519.pub` |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | OCID of the created instance |
| public_ip | Public IP address of the instance |

## Note on A1 Flex Capacity

A1 Flex instances often show "Out of host capacity" errors. You may need to:
- Retry multiple times
- Try different regions
- Use E2.Micro shape instead
