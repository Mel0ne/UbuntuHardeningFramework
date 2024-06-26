#!/usr/bin/env bash

set -euo pipefail

# Checks if the script is being run as root
check_root() {
  local uuid
  uuid=$(id -u)
  if [[ ${uuid} -ne 0 ]]; then
    echo "This script must be run as root. Exiting..." >&2
    exit 1
  fi
}

#######################################
# description
# Arguments:
#   0
#######################################
usage() {
  echo "Usage: $0 <recipient_email_addresses> <sender_email_address>"
  echo "Example: $0 recipient1@ex.com,recipient2@ex.com sender@ex.com"
  exit 1
}

# Log messages to a log file
log() {
  local message="$1"
  local date
  date=$(date +'%Y-%m-%d %H:%M:%S')
  echo "${date} - ${message}"
}

# Enable and start a service
enable_service() {
  local service_name="$1"
  systemctl enable "${service_name}" --no-pager
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

# Show aureport
show_auditd_aureport() {
  log "Showing aureport..."
  aureport --summary
}

# View Auditd configuration
view_auditd_config() {
  log "Viewing Auditd configuration..."
  auditctl -l

  log "Viewing Auditd rules..."
  cat /etc/audit/rules.d/custom-audit-rules.rules

  log "Viewing Auditd configuration..."
  cat /etc/audit/auditd.conf
}

# Write an audit email reporting script to the specified location
write_auditd_reporting() {
  local script_location="$1"
  local email_recipients="$2"
  local sender="$3"

  cat << EOF > "${script_location}"
#!/usr/bin/env bash

# Log a message to the log file
log() {
  local message="\$1"
  local date
  date=\$(date +'%Y-%m-%d %H:%M:%S')
  echo "\${date} - \${message}" >> "\${log_file}"
}

# Generate and output an audit report
generate_aurp_report() {
  local report
  report=\$(aureport --summary -i -ts today)
  echo "\${report}"
}

# Send a recipient with the audit report using sendmail
send_auditd_report() {
  # Set the recipient address where the report will be sent
  local recipient="\$1"
  local mail_tool="\$2"
  local subject="\$3"
  local report="\$4"

  # Check if the report contains relevant information
  if [[ -n \${report} ]]; then
    # Send a recipient with the report using sendmail
    if ! echo -e "Subject: \${subject}\nTo: \${recipient}\nFrom: ${sender}\n\n\${report}" | \${mail_tool} -f "${sender}" -t "\${recipient}"; then
      log "Error: Failed to send email."
    else
      log "Email sent: \${subject}"
    fi
    log "Audit report sent."
  else
    # If no relevant information found, log a message
    log "No relevant audit information found."
  fi
}

# Main function
main() {
  log_file="/var/log/audit-report.log"
  local mail_tool="sendmail"

  subject="[$(hostname -f)] - [Auditd Review Report] - [\$(date +'%Y-%m-%d')]"

  local report
  report="\$(generate_aurp_report)"

  # Add Comma separated email addresses of the recipients to the variable
  local recipients="${email_recipients}"  # Directly inserting the variable value
  send_auditd_report "\${recipients}" "\${mail_tool}" "\${subject}" "\${report}"
}

main "\$@"
EOF

  chmod +x "${script_location}"
  chown root:root "${script_location}"
  chown root:root "${script_location}"

  log "Audit reporting script copied to ${script_location}"
}

# Configure Auditd rules
configure_audit_rules() {
  log "Configuring Auditd rules..."

  # Define custom audit rules
  # TODO - Extend ruleset
  cat << EOL > /etc/audit/rules.d/custom-audit-rules.rules
# Monitor system changes
-w /etc/passwd -p wa
-w /etc/shadow -p wa
-w /etc/sudoers -p wa
-w /etc/group -p wa

# Monitor login and authentication events
-w /var/log/auth.log -p wa
-w /var/log/secure -p wa

# Monitor executable files
-a always,exit -F arch=b64 -S execve
-a always,exit -F arch=b32 -S execve
EOL

  log "Custom Auditd rules configured."
}

# Configure Auditd logging
configure_auditd_logging() {
  log "Configuring Auditd logging..."
  # Look for the log_format and log_file settings in the auditd.conf file and update them if necessary
  sed -i 's/^log_format =.*/log_format = RAW/g' /etc/audit/auditd.conf
  sed -i 's/^log_file =.*/log_file = \/var\/log\/audit\/audit.log/g' /etc/audit/auditd.conf
  log "Auditd logging configured."
}

# Updates the cron job for a script
# shellcheck disable=SC2091
update_cron_job() {
  if [[ -z "$1" ]] || [[ -z "$2" ]]; then
    log "Usage: update_cron_job <script_path> <log_file_path>"
    return 1
  fi

  local script="$1"
  local log_file="$2"
  local cron_entry="0 0 * * * ${script} >${log_file} 2>&1"

  # Attempt to read existing cron jobs, suppressing errors about no existing crontab
  local current_cron_jobs
  if ! current_cron_jobs=$(crontab -l 2> /dev/null); then
    log "No existing crontab for user. Creating new crontab..."
  fi

  # Check if the cron job already exists and is up-to-date
  if echo "${current_cron_jobs}" | grep -Fxq -- "${cron_entry}"; then
    log "Cron job already up to date."
    return 0
  else
    log "Cron job for script not found or not up-to-date. Adding new job..."
  fi

  # Add the cron job to the crontab
  if (echo "${current_cron_jobs}"; echo "${cron_entry}") | crontab -; then
    log "Cron job added successfully."
  else
    log "Failed to add cron job."
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
  echo "Initializing Auditd..."

  local recipients="${1:-root@$(hostname -f)}" # Default recipient email if not provided
  local sender="${2:-root@$(hostname -f)}" # Default sender email if not provided

  install_apt_packages "auditd"
  configure_audit_rules
  configure_auditd_logging

  status_service "auditd"
  start_service "auditd"
  enable_service "auditd"
  restart_service "auditd"

  #  view_auditd_config
  show_auditd_aureport

  local script_location="/usr/local/bin/audit-report.sh"
  local log_file="/var/log/audit-report.log"

  write_auditd_reporting "${script_location}" "${recipients}" "${sender}"
  update_cron_job "${script_location}" "${log_file}"

  echo "Auditd initialization complete."
}

main "$@"