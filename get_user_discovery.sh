#!/bin/sh
# get_user_discovery.sh — LLD for HestiaCP users
# Zabbix agent key: hestia.users.discovery
#
# Uses v-list-users json + jq. Requires: jq, v-list-users.

if command -v v-list-users >/dev/null 2>&1; then
    V_LIST_USERS=$(command -v v-list-users)
elif [ -x /usr/local/hestia/bin/v-list-users ]; then
    V_LIST_USERS=/usr/local/hestia/bin/v-list-users
else
    echo '{"data":[]}'
    exit 1
fi

"$V_LIST_USERS" json 2>/dev/null | jq '
{
  data: [
    to_entries[]
    | select(.key != "admin" and .key != "system")
    | {
        "{#USER}": .key,

        "{#PLAN}": (.value.PACKAGE // "unknown"),
        "{#PLAN_NORM}": ((.value.PACKAGE // "unknown")
                          | ascii_upcase
                          | gsub("[^A-Z0-9]"; "_")),

        "{#ROLE}": (.value.ROLE // "user"),
        "{#SUSPENDED}": (.value.SUSPENDED // "no"),

        "{#WEB_DOMAINS}": (.value.WEB_DOMAINS // "0"),
        "{#MAIL_ACCOUNTS}": (.value.MAIL_ACCOUNTS // "0"),
        "{#DATABASES}": (.value.DATABASES // "0"),
        "{#CRON_JOBS}": (.value.CRON_JOBS // "0"),

        "{#DISK_QUOTA}": (.value.DISK_QUOTA // "0"),
        "{#BANDWIDTH}": (.value.BANDWIDTH // "0"),
        "{#CPU_QUOTA}": (.value.CPU_QUOTA // ""),
        "{#MEMORY_LIMIT}": (.value.MEMORY_LIMIT // "")
      }
  ]
}
'
