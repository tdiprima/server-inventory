#!/usr/bin/env bash
# App discovery 01: system inventory (OS, disks, mounts, services, software, users, logs).
# SPEED: FAST (under 1 minute). SAFETY: GREEN, read-only. Run with sudo to see everything.
# Usage: sudo bash 01_system.sh            (NO_COLOR=1 to disable color)

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s[FOUND]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }
miss() { printf '%s[NONE]%s %s\n' "$R" "$N" "$*"; }
T=""; command -v timeout >/dev/null && T="timeout 30"
# run: show the command, run it with a time limit, cap output lines
run()  { printf '%s$ %s%s\n' "$C" "$*" "$N"; $T bash -c "$*" 2>&1 | head -n "${MAXLINES:-40}"; }

[ "$(id -u)" -ne 0 ] && warn "Not root. Some sections will be incomplete. Re-run with sudo."
printf '%sApp system inventory - %s - %s%s\n' "$B" "$(hostname)" "$(date)" "$N"

hdr "1. Operating system"
run 'cat /etc/*release* 2>/dev/null; cat /etc/issue 2>/dev/null'
run 'uname -a'

hdr "2. Identity and uptime"
run 'hostname; hostname -f; uptime; whoami; id'

hdr "3. CPU and memory"
run 'grep -c ^processor /proc/cpuinfo; grep -m1 "model name" /proc/cpuinfo'
run 'free -m'

hdr "4. Disks and partitions"
run 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null || cat /proc/partitions'
run 'pvs 2>/dev/null; vgs 2>/dev/null; lvs 2>/dev/null'

hdr "5. Mounts (pseudo filesystems hidden)"
run "grep -v -E ' (proc|sysfs|cgroup2?|tmpfs|devtmpfs|devpts|securityfs|pstore|debugfs|mqueue|hugetlbfs|autofs|configfs|fusectl|binfmt_misc|tracefs|bpf|rpc_pipefs|nsfs|overlay|squashfs) ' /proc/mounts"
run 'df -hP -l'
warn "Network mounts below are data on ANOTHER machine. The server owner must know about them."
if grep -q -E ' (nfs4?|cifs|smbfs|glusterfs|fuse\.sshfs) ' /proc/mounts; then
  grep -E ' (nfs4?|cifs|smbfs|glusterfs|fuse\.sshfs) ' /proc/mounts | while read -r src mp fs _; do ok "network mount: $src on $mp ($fs)"; done
else miss "no network mounts active"; fi
run 'grep -v "^#" /etc/fstab; ls /etc/auto.* 2>/dev/null'

hdr "6. File counts per filesystem (inodes used = roughly number of files)"
warn "Use IUsed to guess how long script 04 takes: about 1 minute per 300,000 files on old disks."
run 'df -iP -l'

hdr "7. Interesting processes"
run "ps -eo pid,user,etime,rss,args | grep -i -E 'mongo|java|php|httpd|apache|nginx|tomcat|node|python|docker|mysql|postgres|iipsrv||fcgi|camic' | grep -v grep | cut -c1-220"
hdr "8. Top 15 processes by memory"
run 'ps aux --sort=-%mem 2>/dev/null | head -16 | cut -c1-200'

hdr "9. Listening network ports"
run 'ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null'
warn "27017 = MongoDB, 28017 = old Mongo web UI, 80/443 = web, 9099 =  (old caMicroscope data API)."

hdr "10. Services running / enabled at boot"
run 'systemctl list-units --type=service --state=running --no-pager 2>/dev/null || service --status-all 2>&1'
run 'systemctl list-unit-files --state=enabled --no-pager 2>/dev/null || chkconfig --list 2>/dev/null | grep ":on" || ls /etc/rc2.d /etc/rc3.d'

hdr "11. Key software versions"
for b in mongod mongo mongosh mongodump php httpd apache2 nginx java python python3 node docker docker-compose mysql psql iipsrv.fcgi; do
  p=$(command -v "$b" 2>/dev/null)
  if [ -n "$p" ]; then
    case "$b" in
      java) v=$(java -version 2>&1 | head -1) ;;
      httpd|apache2) v=$($b -v 2>&1 | head -1) ;;
      *) v=$($T "$b" --version 2>&1 | head -1) ;;
    esac
    ok "$b  ($p)  $v"
  fi
done
warn "Binaries outside PATH (e.g. /opt/mongodb/bin) are checked in script 02."

hdr "12. Installed packages of interest"
run "(dpkg -l 2>/dev/null | awk '/^ii/{print \$2, \$3}' || rpm -qa 2>/dev/null) | grep -i -E 'mongo|php|apache|httpd|nginx|openslide|iipimage|tomcat|java|jdk|docker|vips|bioformats'"

hdr "13. Docker"
if command -v docker >/dev/null; then
  run 'docker ps -a 2>&1'
  run 'docker images 2>&1'
  run 'docker volume ls 2>&1'
else miss "docker not installed"; fi
[ -d /var/lib/docker ] && warn "/var/lib/docker exists (sizes measured in script 04)"

hdr "14. Web server config (DocumentRoot, Alias, proxies)"
run "grep -r -h -i -E '^[^#]*(DocumentRoot|Alias|ProxyPass|ScriptAlias|FcgidWrapper|iipsrv|camicroscope)' /etc/apache2 /etc/httpd /etc/nginx 2>/dev/null | sort -u"

hdr "15. Real user accounts and home folders"
run "awk -F: '\$3>=500 && \$7 !~ /(nologin|false)\$/ {print \$1, \$6, \$7}' /etc/passwd"
run 'ls -ld /home/* /root 2>/dev/null'

hdr "16. Recent logins (who used this box)"
run 'last -n 25 -F 2>/dev/null'
run "lastlog 2>/dev/null | grep -v 'Never logged in'"

hdr "17. Scheduled jobs (cron)"
run 'ls -l /etc/cron.d /etc/cron.daily 2>/dev/null; grep -v "^#" /etc/crontab 2>/dev/null'
for u in $(cut -d: -f1 /etc/passwd); do
  c=$(crontab -l -u "$u" 2>/dev/null | grep -v '^#')
  [ -n "$c" ] && { ok "crontab for $u:"; echo "$c" | head -20; }
done

hdr "18. Log folders (newest first)"
run 'ls -lt /var/log | head -30'
run 'ls -lt /var/log/mongodb /var/log/mongo /var/log/apache2 /var/log/httpd /var/log/nginx 2>/dev/null | head -40'

hdr "19. Firewall state (check isolation)"
run 'iptables -L -n 2>/dev/null | head -40; ufw status 2>/dev/null; firewall-cmd --list-all 2>/dev/null'

printf '\n%sDone. Next: script 02 (MongoDB).%s\n' "$G" "$N"
