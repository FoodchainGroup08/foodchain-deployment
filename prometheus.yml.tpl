global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
    cluster:     foodchain
    environment: production

scrape_configs:

  # ── Account 1 services (Docker bridge — resolved by container name) ────────

  - job_name: api-gateway
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['api-gateway:8080']
        labels:
          service: api-gateway
          account: account1

  - job_name: user-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['user-service:8086']
        labels:
          service: user-service
          account: account1

  - job_name: branch-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['branch-service:8081']
        labels:
          service: branch-service
          account: account1

  - job_name: analytics-report-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['analytics-report-service:8085']
        labels:
          service: analytics-report-service
          account: account1

  - job_name: eureka-server
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['eureka-server:8761']
        labels:
          service: eureka-server
          account: account1

  - job_name: config-server
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['config-server:8888']
        labels:
          service: config-server
          account: account1

  # ── Account 2 services (public EC2 IP — set ACCOUNT2_IP in .env) ──────────
  # Prerequisite: Account 2 security group must allow inbound TCP on ports
  # 8082-8084 and 8087 from Account 1's EC2 IP address.

  - job_name: order-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['ACCOUNT2_IP_PLACEHOLDER:8083']
        labels:
          service: order-service
          account: account2

  - job_name: menu-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['ACCOUNT2_IP_PLACEHOLDER:8082']
        labels:
          service: menu-service
          account: account2

  - job_name: kitchen-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['ACCOUNT2_IP_PLACEHOLDER:8084']
        labels:
          service: kitchen-service
          account: account2

  - job_name: notifications-service
    metrics_path: /api/actuator/prometheus
    static_configs:
      - targets: ['ACCOUNT2_IP_PLACEHOLDER:8087']
        labels:
          service: notifications-service
          account: account2
