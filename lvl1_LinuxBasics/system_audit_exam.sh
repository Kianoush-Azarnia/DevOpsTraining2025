#!/bin/bash

# system_audit_exam.sh - System Audit Script for Linux Practice
# This script performs system audit and gathers important information

# Function to add header to files
add_header() {
    local file="$1"
    local content="$2"
    echo "# $content" > "$file"
}

# 1. Preparing the environment
echo "=== Preparing Environment ==="
AUDIT_DIR="$HOME/exam_results/audit"
BACKUP_DIR="$HOME/exam_results/audit_before_deletions"

# Create audit directory
mkdir -p "$AUDIT_DIR"

# Create empty notes.txt file
touch "$AUDIT_DIR/notes.txt"
add_header "$AUDIT_DIR/notes.txt" "System Audit Notes - $(date)"

# Save current working directory
add_header "$AUDIT_DIR/cwd.txt" "Current Working Directory"
pwd >> "$AUDIT_DIR/cwd.txt"

# 2. Analyzing user accounts
echo "=== Analyzing User Accounts ==="

# 2a. Extract all usernames
add_header "$AUDIT_DIR/users.txt" "All System Usernames from /etc/passwd"
cut -d: -f1 /etc/passwd >> "$AUDIT_DIR/users.txt"

# 2b. Find users with /bin/bash shell
add_header "$AUDIT_DIR/bash_users.txt" "Users with /bin/bash shell"
grep "/bin/bash" /etc/passwd | cut -d: -f1 >> "$AUDIT_DIR/bash_users.txt"

# 2c. Replace /bin/bash with /usr/bin/zsh and save first 5 lines
add_header "$AUDIT_DIR/shell_preview.txt" "Shell Replacement Preview (first 5 lines)"
sed 's/\/bin\/bash/\/usr\/bin\/zsh/g' /etc/passwd | head -5 >> "$AUDIT_DIR/shell_preview.txt"

# 3. Gathering system info
echo "=== Gathering System Information ==="

# 3a. Save kernel name
add_header "$AUDIT_DIR/sysinfo.txt" "System Information"
echo "# Kernel Name:" >> "$AUDIT_DIR/sysinfo.txt"
uname -s >> "$AUDIT_DIR/sysinfo.txt"

# 3b. Add system architecture
echo "" >> "$AUDIT_DIR/sysinfo.txt"
echo "# System Architecture:" >> "$AUDIT_DIR/sysinfo.txt"
arch >> "$AUDIT_DIR/sysinfo.txt"

# 3c. Save first 3 and last 3 lines of /etc/group
add_header "$AUDIT_DIR/group_summary.txt" "Group File Summary - First 3 and Last 3 lines"
echo "# First 3 lines:" >> "$AUDIT_DIR/group_summary.txt"
head -3 /etc/group >> "$AUDIT_DIR/group_summary.txt"
echo "" >> "$AUDIT_DIR/group_summary.txt"
echo "# Last 3 lines:" >> "$AUDIT_DIR/group_summary.txt"
tail -3 /etc/group >> "$AUDIT_DIR/group_summary.txt"

# 4. Discovering config files and logs
echo "=== Discovering Config Files and Logs ==="

# 4a. Find all .conf files in /etc
add_header "$AUDIT_DIR/conf_files.txt" "Configuration Files in /etc"
find /etc -name "*.conf" -type f 2>/dev/null | head -50 >> "$AUDIT_DIR/conf_files.txt"

# 4b. Find 10 biggest files in /var/log
add_header "$AUDIT_DIR/top_logs.txt" "Top 10 Largest Files in /var/log"
find /var/log -type f -exec du -h {} + 2>/dev/null | sort -rh | head -10 >> "$AUDIT_DIR/top_logs.txt"

# 5. Access management
echo "=== Access Management ==="

# 5a. Copy /etc/hosts and rename to hosts.bak
cp /etc/hosts "$AUDIT_DIR/hosts.bak"

# 5b. Change permissions to owner read/write only
chmod 600 "$AUDIT_DIR/hosts.bak"

# 5c. Save ls -l output for hosts.bak
add_header "$AUDIT_DIR/hosts_perm.txt" "Hosts Backup File Permissions"
ls -l "$AUDIT_DIR/hosts.bak" >> "$AUDIT_DIR/hosts_perm.txt"

# 6. Clearing
echo "=== Clearing Phase ==="

# 6a. Copy all content to backup directory
mkdir -p "$BACKUP_DIR"
cp -r "$AUDIT_DIR"/* "$BACKUP_DIR/" 2>/dev/null

# 6b. Remove all files except hosts_perm.txt and notes.txt
cd "$AUDIT_DIR"
find . -maxdepth 1 -type f ! -name "hosts_perm.txt" ! -name "notes.txt" -exec rm -f {} +

# Create zip archive
echo "=== Creating Archive ==="
cd "$HOME/exam_results"
zip -r "audit_$(date +%Y%m%d_%H%M%S).zip" "audit/"

echo "=== Audit Completed Successfully ==="
echo "Results saved in: $AUDIT_DIR"
echo "Backup saved in: $BACKUP_DIR"
echo "Zip archive created in: $HOME/exam_results/"