#!/usr/bin/env bash

# Log a message to the log file
log() {
  local message="$1"
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ${message}" >> "${log_file}"
}

# Send a recipient with the audit report using sendmail
send_auditd_report() {
  # Set the recipient address where the report will be sent
  local recipient="$1"

  local sender
  sender="yane.karov@legendland.com.au"

  # Set the subject for the recipient
  local subject
  subject="[$(hostname)] - [Auditd Review Report] - [$(date +'%Y-%m-%d')]"

  # Generate the audit report using aureport
  local report
  report=$(aureport --summary -i -ts today)

  local mail_tool
  mail_tool="sendmail"

  # Check if the report contains relevant information
  if [[ -n ${report} ]]; then
    # Send a recipient with the report using sendmail
    if ! echo -e "Subject: ${subject}\nTo: ${recipient}\nFrom: ${sender}\n\n${report}" | ${mail_tool} -f "${sender}" -t "${recipient}"; then
      log "Error: Failed to send email."
    else
      log "Email sent: ${subject}"
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
  # Add Comma separated email addresses of the recipients to the variable
  # Example: "yane.karov@gmail.com,example@gmail.com"
  local recipients="yane.karov@gmail.com"
  send_auditd_report "${recipients}"
}

main "$@"
