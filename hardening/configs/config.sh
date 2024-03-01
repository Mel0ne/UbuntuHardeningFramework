#!/usr/bin/env bash

# User mappings for SSH public keys
# Format: "UserName:Algorithm Public_Key Comment"
# Example: "admin:ssh-rsa AAAAB3NzwnBnmkSBpiBsqQ== void@null"
# Example: "void:ssh-rsa AAAAB3NzwnBnmkSBpiBsqQ== void@null,ssh-ed2551 AAIDk7VFe void@null"
allowed_ssh_pk_user_mappings="admin:ssh-rsa AAAAB3NzwnBnmkSBpiBsqQ== void@null
void:ssh-rsa AAAAB3NzwnBnmkSBpiBsqQ== void@null,ssh-ed2551 AAIDk7VFe example.eg@example.com"

# Users allowed to login via SSH
# Format: "UserName"
# Example: "admin"
# Example: "admin,void"
allowed_ssh_users="admin,void"

# IP Whitelist for Fail2Ban
# Format: "IP/CIDR"
# Example: "1.1.1.1/32,2.2.2.2/32"
ip_whitelist="1.1.1.1/32,2.2.2.2/32"

# Email settings for sending notifications
# Sender format: "<email>@<domain>"
# Example: "example@domain.com"
# Recipients format: "<email>@<domain>,<email>@<domain>"
# Example: "example@domain.com,example1@domain.com"
sender="void@ex.com.au"
recipients="void.recip@ex.com,example1@domain.com"

export allowed_ssh_pk_user_mappings allowed_ssh_users ip_whitelist sender recipients