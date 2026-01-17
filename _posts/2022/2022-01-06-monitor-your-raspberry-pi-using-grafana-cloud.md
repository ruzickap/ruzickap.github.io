---
title: Monitor your Raspberry Pi using Grafana Cloud
author: Petr Ruzicka
date: 2022-01-06
description: Monitor your Raspberry Pi using Grafana Cloud
categories: [Linux, Monitoring]
tags: [Raspberry Pi, Grafana Cloud, Prometheus, Loki, monitoring, dashboard]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2022/01/monitor-your-raspberry-pi-using-grafana.html)
{: .prompt-info }

Recently my SD card in Raspberry Pi died, because I was storing there the
Prometheus data used for monitoring. Frequent writes to the SD card probably
destroyed it. Anyway I was looking for an alternative to monitor the RPi
without running it (Grafana, Prometheus) myself.

The Grafana Labs offers [Grafana Cloud](https://grafana.com/products/cloud/) in
free version which is powerful enough to get the monitoring data from your RPi
including logs.

Here are the steps to configure your Raspberry Pi to use Grafana Cloud:

## Grafana Cloud Setup

- Go to [Grafana Cloud](https://grafana.com/products/cloud/) and create a new
  account.
- Select your "Team URL" and region:

  ![Grafana Cloud Team URL](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/grafana-cloud-team-url.avif)

- Then select the "Linux Server" and click "Install integration"

  ![Linux Server Integration](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/linux-server-integration.avif)

- I left the "Debian - based" as a default and changed the "Architecture" to
  "Armv7"
- Copy the content from the Grafana Agent field and paste it to your shell
  connected to RPi

  ![Grafana Agent Configuration](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/grafana-agent-configuration.avif)

- Then continue by "Test integration and finish installation":

  ![Test Integration](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/test-integration.avif){:width="200"}

After these steps the Grafana Agent should be configured and should start
sending data to Grafana Cloud.

## Raspberry Pi

It will be handy to add a few more features and configure Grafana Agent a little
bit...

Do the changes in the terminal:

```bash
# Install blackbox-exporter
apt update
apt install -y prometheus-blackbox-exporter

# Change the grafana agent config file /etc/grafana-agent.yaml
cat > /etc/grafana-agent.yaml << EOF
integrations:
  agent:
    enabled: true
  process_exporter:
    enabled: true
    process_names:
      - comm:
        - grafana-agent
        - prometheus-blac
        - systemd
  node_exporter:
    enabled: true
    enable_collectors:
      - interrupts
      - meminfo_numa
      - mountstats
      - systemd
      - tcpstat
  prometheus_remote_write:
  - basic_auth:
      password: eyxxxxxxxxxxxxxxxF9
      username: 2xxxxxx2
    url: https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push
loki:
  configs:
  - clients:
    - basic_auth:
        password: eyxxxxxxxxxxxxxxxF9
        username: 1yyyyyyyy6
      url: https://logs-prod-eu-west-0.grafana.net/api/prom/push
    name: integrations
    positions:
      filename: /tmp/positions.yaml
    target_config:
      sync_period: 10s
    scrape_configs:
      - job_name: system
        static_configs:
        - labels:
            __path__: /var/log/{*log,daemon,messages}
            job: varlogs
          targets:
          - localhost
prometheus:
  configs:
    - name: agent
      scrape_configs:
        - job_name: grafana-agent
          static_configs:
            - targets: ['127.0.0.1:12345']
        - job_name: blackbox-http_2xx
          metrics_path: /probe
          params:
            module: [http_2xx]
          static_configs:
            - targets:
              - http://192.168.1.1
              - https://google.com
              - https://root.cz
          relabel_configs:
            - source_labels: [__address__]
              target_label: __param_target
            - source_labels: [__param_target]
              target_label: instance
            - target_label: __address__
              replacement: 127.0.0.1:9115
        - job_name: blackbox-icmp
          metrics_path: /probe
          params:
            module: [icmp]
          scrape_interval: 5s
          static_configs:
            - targets:
              - 192.168.1.1
              - google.com
              - root.cz
          relabel_configs:
            - source_labels: [__address__]
              target_label: __param_target
            - source_labels: [__param_target]
              target_label: instance
            - target_label: __address__
              replacement: 127.0.0.1:9115
      remote_write:
      - basic_auth:
          password: eyxxxxxxxxxxxxxxxF9
          username: 2xxxxxx2
        url: https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push
  global:
    scrape_interval: 60s
  wal_directory: /tmp/grafana-agent-wal
server:
  http_listen_port: 12345
EOF

# Change the grafana agent config file /etc/prometheus/blackbox.yml and add preferred protocol
cat > /etc/prometheus/blackbox.yml << EOF
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: ip4
  tcp_connect:
    prober: tcp
    tcp:
      preferred_ip_protocol: ip4
  icmp:
    prober: icmp
    icmp:
      preferred_ip_protocol: ip4
EOF

systemctl restart prometheus-blackbox-exporter grafana-agent
```

Then go to the Grafana Cloud again...

## Grafana Cloud Dashboards

- Login to Grafana Cloud again and click on Grafana:

  ![Grafana Cloud Dashboard](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/grafana-cloud-dashboard.avif)

- Click on Import:

  ![Import Dashboard](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/import-dashboard.avif)

- Import these Dashboards with numbers

  - [13659](https://grafana.com/grafana/dashboards/13659) - [Blackbox Exporter (HTTP prober)](https://grafana.com/grafana/dashboards/13659)
  - [9719](https://grafana.com/grafana/dashboards/9719) - [Decentralized Blackbox Exporter](https://grafana.com/grafana/dashboards/9719)
  - [12412](https://grafana.com/grafana/dashboards/12412) - [ICMP exporter](https://grafana.com/grafana/dashboards/12412)
  - [7587](https://grafana.com/grafana/dashboards/7587) - [Prometheus Blackbox Exporter](https://grafana.com/grafana/dashboards/7587)
  - [4202](https://grafana.com/grafana/dashboards/4202) - [Named processes by host](https://grafana.com/grafana/dashboards/4202)
  - [715](https://grafana.com/grafana/dashboards/715) - [Named processes stacked](https://grafana.com/grafana/dashboards/715)
  - [8378](https://grafana.com/grafana/dashboards/8378) - [System Processes Metrics](https://grafana.com/grafana/dashboards/8378)
  - [5984](https://grafana.com/grafana/dashboards/5984) - [Alerts - Linux Nodes](https://grafana.com/grafana/dashboards/5984)
  - [1860](https://grafana.com/grafana/dashboards/1860) - [Node Exporter Full](https://grafana.com/grafana/dashboards/1860)
  - [405](https://grafana.com/grafana/dashboards/405) - [Node Exporter Server Metrics](https://grafana.com/grafana/dashboards/405)

- Do not forget to select the proper prometheus datasource (ends with "-prom"):

  ![Prometheus Datasource](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/prometheus-datasource.avif)

- After you import the Dashboard you should see them by going to
  "Dashboards -> Browse":

  ![Dashboards Browse](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/dashboards-browse.avif)

  ![Node Exporter Dashboard](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/node-exporter-dashboard.avif)

- You can also see the logs from your RPi collected by Loki:

  ![Loki Logs](/assets/img/posts/2022/2022-01-06-monitor-your-raspberry-pi-using-grafana-cloud/loki-logs.avif)

The YouTube video showing all the steps can be found here:

{% include embed/youtube.html id='Vx9MaBP1Uuo' %}

Enjoy 😉
