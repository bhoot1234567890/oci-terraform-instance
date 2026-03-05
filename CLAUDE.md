# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform configuration for provisioning Oracle Cloud Infrastructure (OCI) compute instances using the ARM-based A1 Flex shape (Always Free eligible).

## Commands

```bash
# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply configuration
terraform apply

# Destroy resources
terraform destroy

# Retry provisioning (handles "Out of host capacity" errors)
./retry-terraform.sh
MAX_ATTEMPTS=100 ./retry-terraform.sh  # With limit
```

## Authentication

OCI credentials are read from `~/.oci/config`. The provider also accepts environment variables: `TENANCY_OCID`, `USER_OCID`, `FINGERPRINT`, `PRIVATE_KEY_PATH`, `REGION`.

## Instance Management via OCI CLI

```bash
# Upgrade instance to max free tier specs (4 OCPUs, 24GB RAM)
oci compute instance update \
  --instance-id <instance-ocid> \
  --shape VM.Standard.A1.Flex \
  --shape-config '{"ocpus": 4, "memory-in-gbs": 24}' \
  --force

# List shapes available in region
oci compute shape list --compartment-id <tenancy-ocid>
```

## Architecture

```
main.tf          # Core instance resource, provider config, outputs
variables.tf     # Input variables with defaults (compartment, image, subnet, SSH key)
terraform.tfvars # (gitignored) Actual values - copy from terraform.tfvars.example
retry-terraform.sh # Retry loop for capacity-constrained provisioning
```

The configuration automatically selects the first availability domain. Shape defaults to 1 OCPU / 6GB RAM but can be scaled up to 4 OCPUs / 24GB RAM (Always Free max).

## A1 Flex Capacity

A1 instances frequently show "Out of host capacity" errors. Mitigations:
- Use `retry-terraform.sh` which retries with jitter
- Upgrade to Pay-As-You-Go (PAYG) for better availability
- Scale existing instances via OCI CLI rather than creating new ones

## Firewall & Open Ports

Open ports for external access:

| Port     | Protocol | Service           | Required For                |
|---------|----------|-------------------|------------------------------|
| 22      | TCP      | SSH               | Server management              |
| 80      | TCP      | HTTP              | Let's Encrypt SSL             |
| 443     | TCP      | HTTPS             | Pterodactyl Panel             |
| 8080    | TCP      | Wings API         | Panel ↔ Wings communication   |
| 8888    | TCP      | Panel             | Pterodactyl Panel             |
| 2022    | TCP      | SFTP              | File access to servers         |
| 25565-25570 | TCP      | Minecraft         | Game servers (assign per server) |
| 19132    | UDP      | Minecraft Bedrock | Bedrock servers                  |

### OCI Security List (Cloud Firewall)

```bash
# Security List ID
SECURITY_LIST_ID="ocid1.securitylist.oc1.ap-mumbai-1.aaaaaaaa2ny4hqd3zsld743nmen47zoxzazoqdokdsm2yhlsdxzb2nalgltq"

# View current rules
oci network security-list get --security-list-id $SECURITY_LIST_ID --query 'data."ingress-security-rules"'

# Add new ingress rule (example)
oci network security-list update --security-list-id $SECURITY_LIST_ID \
  --ingress-security-rules '[...]' --force
```

### OS Firewall (UFW on instance)

```bash
# SSH into instance
ssh oci

# Open port
sudo ufw allow <port>/<tcp|udp> comment '<description>'

# View status
sudo ufw status
```
