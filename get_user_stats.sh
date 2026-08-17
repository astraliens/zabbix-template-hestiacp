#!/bin/sh
# get_user_stats.sh — per-user HestiaCP + process stats (JSON)
# Zabbix agent key: hestia.users.stats
#
# Collects:
#   - one `ps` + awk: cpu, %mem, proc, phpfpm
#   - membyte: sum of PSS from /proc/<pid>/smaps_rollup (kB → bytes)
#   - Hestia fields via v-list-users json + jq
#
# Requires: jq, v-list-users, and permission to read smaps_rollup (usually root via sudo).

NUM_CORES=$(nproc 2>/dev/null || echo 1)
[ "$NUM_CORES" -ge 1 ] 2>/dev/null || NUM_CORES=1

if command -v v-list-users >/dev/null 2>&1; then
    V_LIST_USERS=$(command -v v-list-users)
elif [ -x /usr/local/hestia/bin/v-list-users ]; then
    V_LIST_USERS=/usr/local/hestia/bin/v-list-users
else
    echo '{"data":[]}'
    exit 1
fi

USER_DATA_JSON=$("$V_LIST_USERS" json 2>/dev/null)
if [ -z "$USER_DATA_JSON" ]; then
    echo '{"data":[]}'
    exit 1
fi

MONITOR_USERS=$(printf '%s' "$USER_DATA_JSON" | jq -r '
  to_entries[]
  | select(.key != "admin" and .key != "system")
  | .key
' | tr '\n' '|' | sed 's/|$//')

if [ -z "$MONITOR_USERS" ]; then
    echo '{"data":[]}'
    exit 0
fi

STATS_JSON=$(ps -eo user:32,%cpu,%mem,pid,comm --no-headers 2>/dev/null | awk -v cores="$NUM_CORES" -v allow="$MONITOR_USERS" '
BEGIN {
    n = split(allow, a, "|")
    for (i = 1; i <= n; i++) {
        if (a[i] != "") ok[a[i]] = 1
    }
}
NF >= 5 && ($1 in ok) {
    u = $1
    pid = $4 + 0
    u_cpu[u] += $2 + 0
    u_mem[u] += $3 + 0
    u_proc[u]++
    if ($5 ~ /php-fpm/) u_phpfpm[u]++
    if (pid > 0) pid_user[pid] = u
}
END {
    for (pid in pid_user) {
        f = "/proc/" pid "/smaps_rollup"
        while ((getline line < f) > 0) {
            if (line ~ /^Pss:/) {
                split(line, fields)
                u_pss[pid_user[pid]] += fields[2] + 0
                break
            }
        }
        close(f)
    }
    printf "{"
    n = 0
    for (u in u_proc) {
        if (n++) printf ","
        mb = (u in u_pss) ? (u_pss[u] * 1024) : 0
        printf "\"%s\":{\"cpu\":%s,\"mem\":%s,\"membyte\":%d,\"proc\":%d,\"phpfpm\":%d}", \
            u, (u_cpu[u] / cores), u_mem[u] + 0, mb, u_proc[u] + 0, u_phpfpm[u] + 0
    }
    printf "}"
}
')
[ -n "$STATS_JSON" ] || STATS_JSON='{}'

# disk_quota_pct / bandwidth_quota_pct: used/quota*100; 0 if quota is unlimited, empty, or 0
printf '%s' "$USER_DATA_JSON" | jq --argjson stats "$STATS_JSON" '
def num_or_0: tonumber? // 0;
def quota_pct(used; quota):
  (quota // "0" | tostring | ascii_downcase) as $q
  | if ($q == "unlimited" or $q == "" or $q == "0") then 0
    else
      ($q | num_or_0) as $lim
      | if $lim <= 0 then 0 else ((used | num_or_0) / $lim * 100) end
    end;
{
  data: [
    to_entries[]
    | select(.key != "admin" and .key != "system")
    | .key as $u
    | ((.value.U_DISK // "0") | num_or_0) as $udisk
    | ((.value.U_BANDWIDTH // "0") | num_or_0) as $ubw
    | {
        user: $u,
        plan: (.value.PACKAGE // "unknown"),
        plan_norm: ((.value.PACKAGE // "unknown") | ascii_upcase | gsub("[^A-Z0-9]"; "_")),
        suspended: (.value.SUSPENDED // "no"),
        u_disk: $udisk,
        u_disk_web: ((.value.U_DISK_WEB // "0") | num_or_0),
        u_disk_mail: ((.value.U_DISK_MAIL // "0") | num_or_0),
        u_disk_db: ((.value.U_DISK_DB // "0") | num_or_0),
        u_bandwidth: $ubw,
        disk_quota_pct: quota_pct($udisk; .value.DISK_QUOTA),
        bandwidth_quota_pct: quota_pct($ubw; .value.BANDWIDTH),
        u_web_domains: ((.value.U_WEB_DOMAINS // "0") | num_or_0),
        u_mail_accounts: ((.value.U_MAIL_ACCOUNTS // "0") | num_or_0),
        u_cron_jobs: ((.value.U_CRON_JOBS // "0") | num_or_0)
      }
      + ($stats[$u] // {cpu: 0, mem: 0, membyte: 0, proc: 0, phpfpm: 0})
  ]
}
'
