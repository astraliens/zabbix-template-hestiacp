# HestiaCP User Monitoring for Zabbix

Zabbix 7.0 template for **per-user** monitoring of HestiaCP servers (Zabbix Agent 2).

Discovers Hestia users (except `admin` and `system`) and tracks CPU, memory, processes, PHP-FPM, disk, bandwidth, package quotas, and account state.

Most of data collecting using HestiaCP CLI.

## Requirements


| Component     | Notes                                                                       |
| ------------- | --------------------------------------------------------------------------- |
| Zabbix Server | 7.0                                                                         |
| Agent         | Zabbix Agent 2 on each Hestia host                                          |
| Host packages | `jq`, Hestia CLI (`v-list-users`)                                           |
| Privileges    | collectors run as root via sudo (needed to read `/proc/<pid>/smaps_rollup`) |




## How it works

- Discovery (`hestia.users.discovery`) runs every 10 minutes via `v-list-users`.
- One master item (`hestia.users.stats`, 30s) returns JSON for all users. Per-user items are dependent (JSONPath).
- CPU is the user's share of host CPU (`ps` `%cpu` / number of cores).
- Memory (`membyte`) is **PSS** from `smaps_rollup`, not RSS. Shared libraries are split between processes.
- Disk and bandwidth values from Hestia are in MB; items store bytes. Quota alerts use the user's package limits (`DISK_QUOTA`, `BANDWIDTH`). If a quota is unlimited or `0`, the percentage is `0` and that alert does not fire.



## Template

**Name:** `Template HestiaCP User Monitoring`

### Items (per user)


| Item                   | Key                                        | Source                    |
| ---------------------- | ------------------------------------------ | ------------------------- |
| CPU usage              | `hestia.user.cpu[{#USER}]`                 | `ps`                      |
| Memory (PSS)           | `hestia.user.membyte[{#USER}]`             | `smaps_rollup`            |
| Memory % of host       | `hestia.user.mem[{#USER}]`                 | `ps` (no trigger)         |
| Process count          | `hestia.user.proc[{#USER}]`                | `ps`                      |
| PHP-FPM processes      | `hestia.user.phpfpm[{#USER}]`              | `ps`                      |
| Plan                   | `hestia.user.plan[{#USER}]`                | Hestia `PACKAGE`          |
| Suspended              | `hestia.user.suspended[{#USER}]`           | Hestia `SUSPENDED`        |
| Disk used              | `hestia.user.u_disk[{#USER}]`              | Hestia `U_DISK`           |
| Disk web / mail / db   | `hestia.user.u_disk_*[{#USER}]`            | Hestia                    |
| Bandwidth used         | `hestia.user.u_bandwidth[{#USER}]`         | Hestia `U_BANDWIDTH`      |
| Disk quota used %      | `hestia.user.disk_quota_pct[{#USER}]`      | `U_DISK / DISK_QUOTA`     |
| Bandwidth quota used % | `hestia.user.bandwidth_quota_pct[{#USER}]` | `U_BANDWIDTH / BANDWIDTH` |
| Web domains            | `hestia.user.u_web_domains[{#USER}]`       | Hestia                    |
| Mail accounts          | `hestia.user.u_mail_accounts[{#USER}]`     | Hestia                    |
| Cron jobs              | `hestia.user.u_cron_jobs[{#USER}]`         | Hestia                    |




### Triggers


| Trigger                                            | Default                    |
| -------------------------------------------------- | -------------------------- |
| Average CPU above normal                           | 30m avg > 25%              |
| High CPU                                           | 5m avg > 50%               |
| High CPU, long time (blocking candidate)           | 15m avg > 50%              |
| Extremely high CPU                                 | 3m avg > 70%               |
| Extremely high CPU, long time (blocking candidate) | 7m avg > 70%               |
| High memory (PSS)                                  | 35m avg > 768 MB           |
| Excessive processes                                | 5m avg > 25                |
| Excessive PHP-FPM processes                        | 5m avg > 10                |
| Disk near package quota                            | last > 95% of `DISK_QUOTA` |
| Bandwidth near package quota                       | last > 95% of `BANDWIDTH`  |
| Plan changed                                       | INFO, manual close         |
| Suspended state changed                            | INFO, manual close         |


CPU “long time” triggers recover with 5% hysteresis, same as the other CPU levels.

### Graphs

CPU, memory (PSS), disk — one set per user.

### Macros

Change on the template or per host.


| Macro                          | Default | Meaning                      |
| ------------------------------ | ------- | ---------------------------- |
| `{$CPU.AVG.LIMIT}`             | `25`    | %                            |
| `{$CPU.AVG.PERIOD}`            | `30m`   |                              |
| `{$CPU.HIGH.LIMIT}`            | `50`    | %                            |
| `{$CPU.HIGH.PERIOD}`           | `5m`    |                              |
| `{$CPU.HIGH.LONG.PERIOD}`      | `15m`   |                              |
| `{$CPU.EXTREME.LIMIT}`         | `70`    | %                            |
| `{$CPU.EXTREME.PERIOD}`        | `3m`    |                              |
| `{$CPU.EXTREME.LONG.PERIOD}`   | `7m`    |                              |
| `{$MEM.ABS.LIMIT}`             | `768`   | MB (PSS)                     |
| `{$MEM.ABS.PERIOD}`            | `35m`   |                              |
| `{$PROC.HIGH.LIMIT}`           | `25`    | processes                    |
| `{$PROCFPM.HIGH.LIMIT}`        | `10`    | PHP-FPM processes            |
| `{$DISK.QUOTA.PCT.LIMIT}`      | `95`    | % of package disk quota      |
| `{$BANDWIDTH.QUOTA.PCT.LIMIT}` | `95`    | % of package bandwidth quota |


Period macros must include a unit (`s` / `m` / `h`).

---



## 1. Install on each HestiaCP server

Run as root.

```bash
apt-get install -y jq

cd
mkdir -p hestia-zabbix
cd hestia-zabbix
wget -O - https://github.com/astraliens/zabbix-template-hestiacp/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1

mkdir -p /etc/zabbix/custom_script
cp get_user_discovery.sh get_user_stats.sh /etc/zabbix/custom_script/
cp HestiaCPStat.conf /etc/zabbix/zabbix_agent2.d/HestiaCPStat.conf
chown root:root /etc/zabbix/custom_script/get_user_*.sh
chmod 755 /etc/zabbix/custom_script/get_user_*.sh

printf '%s\n' 'zabbix ALL=(root) NOPASSWD: /etc/zabbix/custom_script/get_user_stats.sh, /etc/zabbix/custom_script/get_user_discovery.sh' > /etc/sudoers.d/zabbix-hestia
chmod 440 /etc/sudoers.d/zabbix-hestia

systemctl restart zabbix-agent2
```

Without `+x` on the scripts, sudo reports `command not found`.

Check:

```bash
sudo -u zabbix sudo -n /etc/zabbix/custom_script/get_user_stats.sh
sudo -u zabbix sudo -n /etc/zabbix/custom_script/get_user_discovery.sh
zabbix_agent2 -t hestia.users.stats
zabbix_agent2 -t hestia.users.discovery
```

`-n` must not ask for a password. Both scripts should print JSON (`{"data":[...]}`).

From the Zabbix server or proxy:

```bash
zabbix_get -s <host_ip> -k hestia.users.stats
```

---



## 2. Import the template into Zabbix Server

1. Zabbix → **Data collection** → **Templates** → **Import**
2. Select `hestia_zabbix.yaml`
3. Import

Link **Template HestiaCP User Monitoring** to each Hestia host.

After import (or after changing item units/preprocessing), open the discovery rule on a host and use **Execute now** or wait 10 minutes for regular update.

---



## Troubleshooting

`sudo: a password is required`  
NOPASSWD is missing or the sudoers path does not match the script path exactly. Re-check `/etc/sudoers.d/zabbix-hestia` with `visudo`.

`…/get_user_stats.sh: command not found`  
No execute bit or wrong path. `ls -l` should show `-rwxr-xr-x`.

`ZBX_NOTSUPPORTED: Unknown metric hestia.users.stats`  
Agent did not load `HestiaCPStat.conf`. Check `Include=`, file path, then `systemctl restart zabbix-agent2`. Test on the **monitored host**, not on the Zabbix server.

`membyte` **is 0**  
The collector cannot read `smaps_rollup` (must run as root via sudo).

**Quota % stays 0**  
Package disk/bandwidth quota is `unlimited`, empty, or `0`.

## Donations

You can say thanks by donating for buying pizza at:

<a href="https://www.buymeacoffee.com/astraliens" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Pizza" height="41" width="174"></a>