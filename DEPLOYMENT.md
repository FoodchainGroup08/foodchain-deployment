# FoodChain — Complete AWS Deployment Guide

Full production deployment across **2 AWS free-tier accounts** using GitHub Actions CI/CD.
Existing `docker-compose.yml` is untouched and still works for local development.

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AWS ACCOUNT 1  (t2.micro · 1 GB RAM)                               │
│                                                                      │
│   :8888  config-server    ◄── GitHub (foodchain-config repo)        │
│   :8761  eureka-server    ◄── all services register here            │
│   :8080  api-gateway      ◄── PUBLIC entry point (Swagger too)      │
│   :8086  user-service     ◄── auth, JWT, email verification         │
│   :8081  branch-service                                              │
└─────────────────────────────────────────────────────────────────────┘
    │ Eureka cross-account registration (public IP)
    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  AWS ACCOUNT 2  (t2.micro · 1 GB RAM)                               │
│                                                                      │
│   :8083  order-service                                               │
│   :8082  menu-service                                                │
│   :8084  kitchen-service                                             │
│   :8085  analytics-report-service                                    │
│   :8087  notifications-service                                       │
└─────────────────────────────────────────────────────────────────────┘
         │         │         │
         ▼         ▼         ▼
  Confluent    Redis      AWS RDS
  Cloud Kafka  Cloud      MySQL
  (free)       (free 30MB) (free tier)
```

---

## Phase 0 — Prerequisites

Before touching AWS you need accounts on three free cloud services.

### 0.1 Docker Hub

1. Sign up at **hub.docker.com** (free account)
2. Note your username — you'll use it everywhere as `DOCKER_USERNAME`
3. Go to **Account Settings → Security → New Access Token**
   - Description: `github-actions`
   - Permissions: Read & Write
   - Save the token as `DOCKER_TOKEN`

### 0.2 Confluent Cloud (Kafka)

1. Sign up at **confluent.cloud** → Create a **Basic** cluster
2. Region: `us-east-1` (or closest to your EC2 region)
3. **Clients → Java** — note the bootstrap server:
   ```
   pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
   ```
4. **API Keys → Add Key** (cluster-level) — save the key and secret
5. **Topics** → Create these (or enable auto-create):

   | Topic | Partitions |
   |-------|------------|
   | `order.received` | 3 |
   | `order.status.updated` | 3 |
   | `order.ready` | 3 |
   | `menu.item.updated` | 3 |
   | `analytics.daily.rollup` | 3 |

### 0.3 Redis Cloud

1. Sign up at **redis.io/try-free** → Free 30 MB plan (no credit card)
2. Region: same as your EC2 instances
3. Create a database → note the **Public Endpoint** (host:port) and **Password**

---

## Phase 1 — AWS RDS MySQL

> One RDS instance is shared across both EC2 accounts.

### 1.1 Create RDS in Account 1

1. **AWS Console → RDS → Create database**
2. Engine: **MySQL 8.0**
3. Template: **Free tier**
4. DB instance: `foodchain-db`
5. Master username: `admin`, set a strong password
6. Instance class: `db.t3.micro`
7. Storage: 20 GB gp2
8. **Public access: Yes** (needed by Account 2 EC2 and local dev)
9. VPC Security Group — add inbound rule:
   - Type: MySQL/Aurora (3306)
   - Source: `0.0.0.0/0` *(restrict to EC2 IPs once you know them)*
10. Click **Create**. Takes ~5 minutes. Note the **Endpoint**.

### 1.2 Create Databases

SSH into Account 1 EC2 (after it's set up) or use MySQL Workbench:

```sql
CREATE DATABASE IF NOT EXISTS user_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS branch_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS order_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS menu_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS analytics_report_db CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS notifications_db CHARACTER SET utf8mb4;
```

---

## Phase 2 — GitHub Secrets (foodchain-deployment repo)

Go to your **foodchain-deployment** GitHub repo → **Settings → Secrets and variables → Actions**.

Add each secret below:

| Secret name | Value |
|-------------|-------|
| `DOCKER_USERNAME` | Your Docker Hub username |
| `DOCKER_TOKEN` | Docker Hub access token |
| `EC2_ACCOUNT1_HOST` | Elastic IP of Account 1 EC2 |
| `EC2_ACCOUNT1_SSH_KEY` | Contents of Account 1 `.pem` file (full text including `-----BEGIN...`) |
| `EC2_ACCOUNT2_HOST` | Elastic IP of Account 2 EC2 |
| `EC2_ACCOUNT2_SSH_KEY` | Contents of Account 2 `.pem` file |

> Also add these same secrets to **each service repo** (api-gateway, user-service, etc.):
> `DOCKER_USERNAME` and `DOCKER_TOKEN` — needed for the build-push workflows.

---

## Phase 3 — GitHub Secrets in Each Service Repo

Each service repo (`api-gateway`, `user-service`, `order-service`, `menu-service`, `branch-service`, `kitchen-service`, `analytics-report-service`, `notifications-service`, `config-server`, `eureka-server`) needs:

| Secret | Value |
|--------|-------|
| `DOCKER_USERNAME` | Your Docker Hub username |
| `DOCKER_TOKEN` | Docker Hub access token |

Go to each repo → **Settings → Secrets → Actions → New repository secret**.

---

## Phase 4 — EC2 Account 1 Setup

### 4.1 Launch EC2

1. **AWS Console → EC2 → Launch Instance**
2. Name: `foodchain-account1`
3. AMI: **Amazon Linux 2023** (free tier eligible)
4. Instance type: **t2.micro**
5. Key pair: Create new → Download `.pem` file → save it safely
6. Network: default VPC
7. Security Group — create new with these inbound rules:

   | Port | Protocol | Source | Purpose |
   |------|----------|--------|---------|
   | 22 | TCP | Your IP only | SSH |
   | 8080 | TCP | 0.0.0.0/0 | API Gateway (public) |
   | 8761 | TCP | 0.0.0.0/0 | Eureka (Account 2 needs this) |
   | 8888 | TCP | 0.0.0.0/0 | Config Server (Account 2 needs this) |
   | 8081 | TCP | 0.0.0.0/0 | Branch Service |
   | 8086 | TCP | 0.0.0.0/0 | User Service |

8. Storage: **20 GB gp2**
9. Launch → note the **Instance ID**

### 4.2 Allocate Elastic IP for Account 1

1. **EC2 → Elastic IPs → Allocate Elastic IP**
2. **Actions → Associate** → select your instance
3. Note this IP as `ACCOUNT1_IP` — it won't change when you stop/start the instance

### 4.3 SSH in and Install Docker

```bash
# From your local machine
chmod 400 your-key-account1.pem
ssh -i your-key-account1.pem ec2-user@<ACCOUNT1_IP>

# Inside EC2:
sudo yum update -y
sudo yum install -y docker git python3

sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install Docker Compose v2
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Make docker-compose v1 alias work too
sudo ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Log out and back in for docker group to take effect
exit
```

### 4.4 Add Swap Space (Critical for 1 GB RAM)

```bash
ssh -i your-key-account1.pem ec2-user@<ACCOUNT1_IP>

sudo dd if=/dev/zero of=/swapfile bs=128M count=16   # creates 2 GB swap
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab

# Verify
free -h
```

### 4.5 Clone Deployment Repo

```bash
git clone https://github.com/your-org/foodchain-deployment.git
cd foodchain-deployment

# Create .env from the example
cp .env.account1.example .env
nano .env   # fill in all real values
```

**Fill in `.env` with your real values:**
- `DOCKER_USERNAME` — your Docker Hub username
- `RDS_ENDPOINT` — from Step 1
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` — from Phase 0.3
- `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_API_KEY`, `KAFKA_API_SECRET` — from Phase 0.2
- `CONFIG_REPO_URI` — e.g. `https://github.com/your-org/foodchain-config`
- `JWT_SECRET` — strong 32+ char string
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` — from Google Cloud Console
- `EMAIL_USER`, `EMAIL_PASS` — Gmail + app password

### 4.6 First Deploy (Manual)

```bash
cd ~/foodchain-deployment

# Pull images from Docker Hub
docker-compose -f docker-compose.account1.yml pull

# Start services
docker-compose -f docker-compose.account1.yml up -d

# Watch startup (takes 2-3 minutes)
docker-compose -f docker-compose.account1.yml logs -f
```

**Expected startup order:** config-server → eureka-server → api-gateway, user-service, branch-service

---

## Phase 5 — EC2 Account 2 Setup

### 5.1 Launch EC2 (in Account 2)

Same as Account 1 but with different Security Group rules:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP only | SSH |
| 8082 | TCP | 0.0.0.0/0 | Menu Service |
| 8083 | TCP | 0.0.0.0/0 | Order Service |
| 8084 | TCP | 0.0.0.0/0 | Kitchen Service |
| 8085 | TCP | 0.0.0.0/0 | Analytics Service |
| 8087 | TCP | 0.0.0.0/0 | Notifications Service |

> Account 2 services register with Eureka on Account 1 but all traffic goes through the gateway on Account 1.
> You do NOT need to expose Account 2 ports publicly — only to the gateway.
> For tighter security: change Source from `0.0.0.0/0` to Account 1's Elastic IP.

### 5.2 Install Docker + Swap

Same commands as Account 1 — install Docker, add swap space.

### 5.3 Clone and Configure

```bash
git clone https://github.com/your-org/foodchain-deployment.git
cd foodchain-deployment
cp .env.account2.example .env
nano .env
```

**Key difference in Account 2's `.env`:**
```
ACCOUNT1_IP=<the Elastic IP you noted from Phase 4.2>
```
All other values are the same as Account 1 (same RDS, Redis, Kafka).

### 5.4 First Deploy

```bash
docker-compose -f docker-compose.account2.yml pull
docker-compose -f docker-compose.account2.yml up -d
docker-compose -f docker-compose.account2.yml logs -f
```

Account 2 services will retry connecting to Eureka on Account 1 until it's ready.
`restart: unless-stopped` handles this automatically.

---

## Phase 6 — Build Docker Images (First Time)

Before the deploy workflows can run, you need images on Docker Hub.
Push all service code to `main` branch — the build-push workflows in each repo will fire automatically.

**Or trigger them manually:**

In each service repo on GitHub:
**Actions → Build & Push — [service-name] → Run workflow**

Do this for all 10 repos:
- `config-server`
- `eureka-server`
- `api-gateway`
- `user-service`
- `branch-service`
- `order-service`
- `menu-service`
- `kitchen-service`
- `analytics-report-service`
- `notifications-service`

Each build takes ~3-5 minutes (Maven build inside Docker). They can all run in parallel.

**Verify on Docker Hub:**
```
https://hub.docker.com/u/YOURDOCKERHUBUSERNAME
```
You should see all 10 repositories.

---

## Phase 7 — GitHub Actions Deploy Workflows

Two workflows live in `foodchain-deployment/.github/workflows/`:

| Workflow | Trigger | Target |
|----------|---------|--------|
| `deploy-account1.yml` | Manual (workflow_dispatch) | Account 1 EC2 |
| `deploy-account2.yml` | Manual (workflow_dispatch) | Account 2 EC2 |

### Running a deployment

1. Go to `foodchain-deployment` repo on GitHub
2. **Actions** tab → select the workflow
3. **Run workflow** → click the green button
4. Watch the logs — it SSHes into the EC2, pulls updated images, restarts services, and runs a health check

### Deploying a code change end-to-end

```
1. Push change to e.g. order-service main branch
2. order-service build-push.yml runs → new image pushed to Docker Hub
3. Go to foodchain-deployment → Actions → Deploy Account 2 → Run workflow
4. Workflow SSHes to Account 2 EC2, pulls new image, restarts order-service
```

---

## Phase 8 — Verification Checklist

### On Account 1 EC2

```bash
# All 5 containers running
docker-compose -f docker-compose.account1.yml ps

# Health checks
curl http://localhost:8888/actuator/health    # config-server
curl http://localhost:8761/actuator/health    # eureka-server
curl http://localhost:8080/actuator/health    # api-gateway
curl http://localhost:8086/api/actuator/health   # user-service
curl http://localhost:8081/api/actuator/health   # branch-service
```

### On Account 2 EC2

```bash
docker-compose -f docker-compose.account2.yml ps

curl http://localhost:8083/api/actuator/health   # order-service
curl http://localhost:8082/api/actuator/health   # menu-service
curl http://localhost:8084/api/actuator/health   # kitchen-service
curl http://localhost:8085/api/actuator/health   # analytics-service
curl http://localhost:8087/api/actuator/health   # notifications-service
```

### From your local machine (browser)

| URL | Expected |
|-----|----------|
| `http://ACCOUNT1_IP:8761` | Eureka dashboard showing ALL 10 services registered |
| `http://ACCOUNT1_IP:8080/swagger-ui.html` | Swagger UI with all 7 service API docs |
| `http://ACCOUNT1_IP:8080/actuator/health` | `{"status":"UP"}` |

**All 10 services should appear in Eureka** — Account 2 services register remotely via `ACCOUNT1_IP:8761`.

---

## Phase 9 — RDS Security Hardening (After Setup)

Once you know both EC2 Elastic IPs, lock down RDS to only those IPs:

1. **RDS → Your DB → Connectivity & security → VPC security groups**
2. Edit the inbound rule for port 3306
3. Change Source from `0.0.0.0/0` to:
   - `ACCOUNT1_IP/32`
   - `ACCOUNT2_IP/32`
   - Your local IP for debugging

---

## Memory Budget

Both t2.micro instances have 1 GB RAM. With 2 GB swap added, they can handle the load with aggressive JVM tuning (`-XX:+UseSerialGC` reduces GC overhead).

### Account 1 (1 GB RAM + 2 GB swap)

| Service | Heap cap | Est. process |
|---------|----------|--------------|
| config-server | 96m | ~190 MB |
| eureka-server | 96m | ~190 MB |
| api-gateway | 140m | ~240 MB |
| user-service | 140m | ~240 MB |
| branch-service | 110m | ~210 MB |
| OS + Docker | — | ~100 MB |
| **Total** | | **~1170 MB** |

### Account 2 (1 GB RAM + 2 GB swap)

| Service | Heap cap | Est. process |
|---------|----------|--------------|
| order-service | 130m | ~230 MB |
| menu-service | 120m | ~220 MB |
| kitchen-service | 110m | ~210 MB |
| analytics-report-service | 130m | ~230 MB |
| notifications-service | 110m | ~210 MB |
| OS + Docker | — | ~100 MB |
| **Total** | | **~1200 MB** |

> Both accounts exceed physical RAM — swap handles the overflow at the cost of slightly slower response on first request after idle. This is fine for a demo/capstone.
>
> If Account 1 gets OOM-killed: move `branch-service` to Account 2 — it has no cross-account dependency.

---

## Config Server → Confluent Cloud (Kafka) Setup

Each service that uses Kafka needs this in its `foodchain-config/{service}.yml`:

```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    properties:
      security.protocol: SASL_SSL
      sasl.mechanism: PLAIN
      sasl.jaas.config: >
        org.apache.kafka.common.security.plain.PlainLoginModule required
        username="${KAFKA_API_KEY}"
        password="${KAFKA_API_SECRET}";
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
    consumer:
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      auto-offset-reset: earliest
```

Services needing Kafka: `order-service`, `kitchen-service`, `menu-service`, `analytics-report-service`, `notifications-service`.

---

## Startup Order Reference

```
Confluent Cloud + Redis Cloud  (external — always available)
        │
        ▼
  config-server           (Account 1 — boots first, ~60s)
        │
        ▼
  eureka-server           (Account 1 — boots after config, ~60s)
        │
        ├──► api-gateway          (Account 1)
        ├──► user-service         (Account 1)
        ├──► branch-service       (Account 1)
        │
        └──► order-service        (Account 2 — retries until Eureka is ready)
             menu-service         (Account 2)
             kitchen-service      (Account 2)
             analytics-report-service (Account 2)
             notifications-service    (Account 2)
```

Account 2 services use `restart: unless-stopped` — they'll retry Eureka registration until Account 1 is fully up.

---

## Useful Commands

### Logs

```bash
# Follow all services on Account 1
docker-compose -f docker-compose.account1.yml logs -f

# Follow one service
docker-compose -f docker-compose.account1.yml logs -f api-gateway

# View last 100 lines
docker-compose -f docker-compose.account1.yml logs --tail=100 user-service
```

### Restart a single service

```bash
docker-compose -f docker-compose.account1.yml restart user-service
```

### Pull and redeploy one service (without touching others)

```bash
docker-compose -f docker-compose.account1.yml pull user-service
docker-compose -f docker-compose.account1.yml up -d user-service
```

### Check memory usage

```bash
docker stats --no-stream
free -h
```

### Eureka registered services

```bash
curl -s http://localhost:8761/eureka/apps | python3 -c "
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for app in root.findall('.//application'):
    name = app.find('name').text
    for inst in app.findall('instance'):
        status = inst.find('status').text
        host = inst.find('ipAddr').text
        print(f'{name}: {status} @ {host}')
"
```

---

## Teardown (Avoid Accidental Billing)

AWS free tier gives **750 hours/month per account** for t2.micro. Two instances running 24/7 = 744 hours — exactly at the limit.

```bash
# Stop containers but keep the EC2
docker-compose -f docker-compose.accountX.yml down
```

**In AWS Console when not demoing:**
- **EC2 → Instances → Stop** (not Terminate — you keep the Elastic IP)
- **RDS → Actions → Stop temporarily** (restarts after 7 days — stop again if needed)

> Stopping EC2 pauses the 750-hour counter. RDS stopped still accrues storage costs (~$2/month for 20 GB gp2, within free tier if under 20 GB).

---

## Local Development (unchanged)

The original `docker-compose.yml` in this repo still runs everything locally with local builds:

```bash
# In foodchain-deployment directory
docker-compose up -d
```

This is completely separate from the AWS deployment files and is unaffected.

---

## Troubleshooting

### Service not appearing in Eureka
- Check Account 2's `.env` has the correct `ACCOUNT1_IP`
- Verify Account 1 Security Group allows port 8761 from anywhere
- `docker logs <container>` — look for `WARN com.netflix.discovery` errors

### OOM / container keeps restarting
```bash
docker stats          # watch live memory
dmesg | grep -i oom  # kernel OOM killer logs
```
If a container is being killed, reduce its `JDK_JAVA_OPTIONS` heap (`-Xmx`) or add more swap.

### Config Server can't connect to GitHub (private repo)
Add a GitHub Personal Access Token (PAT) to CONFIG_REPO_URI:
```
CONFIG_REPO_URI=https://YOUR_PAT@github.com/your-org/foodchain-config
```

### RDS connection refused
- Check RDS Security Group allows port 3306 from EC2 IPs
- Verify `RDS_ENDPOINT` in `.env` matches exactly what AWS shows (no trailing slash)
- Test: `mysql -h $RDS_ENDPOINT -u admin -p` from inside the EC2

### Swagger 404 on Account 1
Make sure port 8080 is open in Account 1 Security Group (inbound, `0.0.0.0/0`).
Try: `curl http://ACCOUNT1_IP:8080/swagger-ui.html` — should return 302.
