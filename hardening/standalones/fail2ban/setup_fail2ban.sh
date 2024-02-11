#!/usr/bin/env bash

# Main function
main_fail2ban_setup() {
  check_root
  echo "Initializing Fail2Ban..."

  local custom_jail="/etc/fail2ban/jail.local"
  local fail2ban_log_file="/var/log/fail2ban-setup.log"
  local ip_list="167.179.173.46/32"

  install_apt_packages "fail2ban"

  create_file_if_not_exists "${fail2ban_log_file}" "${fail2ban_log_file}"
  create_file_if_not_exists "${custom_jail}" "${fail2ban_log_file}"

  ensure_file_is_writable "${fail2ban_log_file}" "${fail2ban_log_file}"
  ensure_file_is_writable "${custom_jail}" "${fail2ban_log_file}"

  status_service "fail2ban"
  start_service "fail2ban"
  enable_service "fail2ban"

  view_fail2ban_config
  backup_jail_config

  # Create a custom Fail2ban jail configuration for SSH protection
  create_jail_config "${custom_jail}" "${ip_list}"
  # Restart Fail2ban service to apply the new configuration
  restart_service "fail2ban"
}