#!/usr/bin/env bash

set -euo pipefail

# Log messages to a log file
log() {
  local message="$1"
  local date
  date=$(date +'%Y-%m-%d %H:%M:%S')
  echo "${date} - ${message}"
}

usage() {
  echo "Usage: $0 <ssh_port> <recipient_email_addresses> <sender_email_address> <ip_list>"
  echo "Example A: $0 22 recipient1@ex.com,recipient2@ex.com sender@ex.com 5.5.5.5/32"
  echo "Example B: $0 22 recipient1@ex.com,recipient2@ex.com sender@ex.com 5.5.5.5/32,6.6.6.6/32"
  exit 1
}

# Checks if the script is being run as root
check_root() {
  local uuid
  uuid=$(id -u)
  if [[ ${uuid} -ne 0 ]]; then
    echo "This script must be run as root. Exiting..." >&2
    exit 1
  fi
}

# Enable and start a service
enable_service() {
  local service_name="$1"
  systemctl enable "${service_name}" --no-pager && {
    log "Enabled ${service_name} service." && {
      start_service "${service_name}"
    }
  } || {
    log "Failed to enable ${service_name} service."
  }
}

# Restart a service
restart_service() {
  local service_name="$1"
  systemctl restart "${service_name}" --no-pager
}

# Start a service
start_service() {
  local service_name="$1"
  systemctl start "${service_name}" --no-pager
}

# Retrieve service status
status_service() {
  local service_name="$1"
  systemctl status "${service_name}" --no-pager
}

# Backup the existing Fail2ban jail configuration
backup_jail_config() {
  local backup_dir="/etc/fail2ban/backup"
  local current_config="/etc/fail2ban/jail.local"
  local timestamp
  timestamp=$(date +"%Y%m%d%H%M%S")

  log "Creating a backup of Fail2ban jail configuration..."

  # Create the backup directory if it doesn't exist
  mkdir -p "${backup_dir}"

  # Copy the current jail configuration to the backup directory
  cp "${current_config}" "${backup_dir}/jail.local_${timestamp}.bak" || {
    log "Failed to create a backup of Fail2ban jail configuration."
    exit 1
  } && {
    log "Backup of Fail2ban jail configuration created."
  }
}

# Create a custom Fail2ban jail configuration for SSH protection
create_jail_config() {
  local ssh_port="${1}"
  local custom_jail="${2}" # Path to the custom jail configuration
  local recipients="${3:-example.eg@example.com}" # Default recipient email if not provided
  local sender="${4:-example1.eg@example.com}" # Default sender email if not provided
  local ip_list="${5:-""}" # Default IP list to empty if not provided
  local ignore_ips

  if [[ ${ip_list} == "" ]]; then
    echo "No IP list provided. Proceeding without ignoring any IPs."
    ignore_ips=""
  else
    ignore_ips="ignoreip = ${ip_list}"
  fi

  # Check if parameters are provided
  if [[ -z ${custom_jail} ]]; then
    echo "Error: No file path provided for the jail configuration."
    return 1
  fi

    # Aggressive jail configuration for SSH
    cat <<- EOF > "${custom_jail}"
        [sshd]
        enabled = true
        port = ${ssh_port}
        filter = sshd
        logpath = /var/log/auth.log
        maxretry = 3
        findtime = 300
        bantime = 604800
        ${ignore_ips}
        destemail = ${recipients}
        sender = ${sender}
        sendername = Fail2Ban
        mta = sendmail
        action = %(action_mwl)s
        bantime.increment = true
EOF
}

# Create a generic file if it doesn't exist
create_file_if_not_exists() {
  local file="$1"
  local error_log_file="$2"
  if [[ ! -f ${file} ]]; then
    echo "attempting to create file: ${file}"
    touch "${file}" || {
      system_log "ERROR" "Unable to create file: ${file}" "${error_log_file}"
      exit 1
    }
  fi
}

# Ensure a file is writable
ensure_file_is_writable() {
  local file="$1"
  local error_log_file="$2"
  if [[ ! -w ${file} ]]; then
    echo "attempting to make file writable: ${file}"
    system_log "ERROR" "File is not writable: ${file}" "${error_log_file}"
    exit 1
  fi
}

# Installs a list of apt packages
install_apt_packages() {
  local package_list=("${@}") # Capture all arguments as an array of packages

  log "Starting package installation process."

  # Verify that there are no apt locks
  while fuser /var/lib/dpkg/lock > /dev/null 2>&1 || fuser /var/lib/apt/lists/lock > /dev/null 2>&1 || fuser /var/cache/apt/archives/lock > /dev/null 2>&1; do
    log "Waiting for other software managers to finish..."
    sleep 1
  done

  if apt update -y; then
    log "Package lists updated successfully."
  else
    log "Failed to update package lists. Continuing with installation..."
  fi

  local package
  local failed_packages=()
  for package in "${package_list[@]}"; do
    if dpkg -l | grep -qw "${package}"; then
      log "${package} is already installed."
    else
      # Sleep to avoid "E: Could not get lock /var/lib/dpkg/lock-frontend" error
      sleep 1
      if apt install -y "${package}"; then
        log "Successfully installed ${package}."
      else
        log "Failed to install ${package}."
        failed_packages+=("${package}")
      fi
    fi
  done

  if [[ ${#failed_packages[@]} -eq 0 ]]; then
    log "All packages were installed successfully."
  else
    log "Failed to install the following packages: ${failed_packages[*]}"
  fi
}

# Main function
main() {
  check_root
  echo "Initializing Fail2Ban..."

  local custom_jail="/etc/fail2ban/jail.local"
  local fail2ban_log_file="/var/log/fail2ban-setup.log"

  if [[ $# -ne 4 ]]; then
    usage
  fi

  local ssh_port="${1:-22}" # Default SSH port if not provided
  local recipients="${2:-root@$(hostname -f)}" # Default recipient email if not provided
  local sender="${3:-root@$(hostname -f)}" # Default sender email if not provided
  local ip_list="${4:-""}" # Default IP list to empty if not provided

  install_apt_packages "fail2ban"

  create_file_if_not_exists "${fail2ban_log_file}" "${fail2ban_log_file}"
  create_file_if_not_exists "${custom_jail}" "${fail2ban_log_file}"

  ensure_file_is_writable "${fail2ban_log_file}" "${fail2ban_log_file}"
  ensure_file_is_writable "${custom_jail}" "${fail2ban_log_file}"

  enable_service "fail2ban"

  backup_jail_config

  # Create a custom Fail2ban jail configuration for SSH protection
  create_jail_config "${ssh_port}" "${custom_jail}" "${recipients}" "${sender}" "${ip_list}"

  # Restart Fail2ban service to apply the new configuration
  restart_service "fail2ban"

  # Verify the status of the Fail2ban service
  status_service "fail2ban"
}

main "$@"