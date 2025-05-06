# Dockerfile Documentation
 This document explains the structure and purpose of the Dockerfile used for building the `frappe_press` image. It sets up a Frappe Press environment in a containerized, cloud-optimized format using multi-stage builds.


### 🧱 Base Image `python:3.11.6-slim-bookworm`
A slim Debian-based image with Python 3.11.6 for reduced size and security surface.
``` 
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE}
```

### ⚙️ Build Arguments & Environment Variables
``` 
PYTHON_VERSION=3.11.6: Python version for the base image.

DEBIAN_BASE=bookworm: Debian distribution base.

WKHTMLTOPDF_VERSION=0.12.6.1-3: Required version for PDF generation.

WKHTMLTOPDF_DISTRO=bookworm: Target OS for wkhtmltopdf package.

NODE_VERSION=18.18.2: Node.js version used for building frontend assets.

NVM_DIR=/home/frappe/.nvm: Directory for Node Version Manager.

PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}: Ensure Node is available in the environment.
``` 

### 👤 User and Permissions
```
useradd -ms /bin/bash frappe
```

### 📦 Installed System Packages
```
apt-get install --no-install-recommends -y \
    curl git vim nginx gettext-base file \
    libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
    restic gpg mariadb-client less libpq-dev postgresql-client \
    wait-for-it jq wget docker.io
```
Purpose:
- General tools: curl, git, vim, wget, etc.
- Database clients: mariadb-client, postgresql-client for MariaDB and PostgreSQL.
- PDF dependencies: libpango, libharfbuzz for wkhtmltopdf.
- Backup tools: restic.
- Web server: nginx.
  
### 🌐 Nginx Setup
- Nginx is cleaned up and customized:
- Removes default config.
- Updates logging and permissions for frappe user.
  
Templates:
```
resources/nginx-template.conf copied to /templates/nginx/frappe.conf.template
```
Entrypoint:
````
resources/nginx-entrypoint.sh is made executable and added to /usr/local/bin/
````

### 🌐 Node.js Installation via NVM
- NVM installed from GitHub.
- Node.js v18.18.2 installed and made default.
- Global install of yarn.

This is essential for Frappe’s frontend build tools.

### 📄 wkhtmltopdf Installation
- Architecture detection for amd64 or arm64.
- Downloads .deb package from GitHub releases.

Installs wkhtmltopdf, which is required for PDF generation in ERPNext/Frappe.

### 🔧 Frappe Bench CLI
````
pip3 install frappe-bench
````

### 🔨 Builder Stage
Used to build and initialize the Frappe bench and apps.

Extra Packages Installed
```
apt-get install --no-install-recommends -y \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev \
    libpq-dev libffi-dev liblcms2-dev libldap2-dev libmariadb-dev libsasl2-dev \
    libtiff5-dev libwebp-dev pkg-config redis-tools rlwrap tk8.6-dev cron \
    gcc build-essential libbz2-dev
```
### Apps Initialization
- If APPS_JSON_BASE64 is provided, it decodes and saves to /opt/frappe/apps.json.
- Bench is initialized with:
```
bench init --apps_path=/opt/frappe/apps.json --frappe-branch=version-15 --no-procfile 
```

### Cleanup
- .git folders in apps/ are removed.
- common_site_config.json is created with {}.

### 🧩 Backend Stage
- Copies the built bench from builder stage.
- Sets up folders for:
  - Certbot: /home/frappe/.certbot/webroot
  - Local builds: .docker-builds
  - Git clones: .clones

### Certbot Installs
- certbot
- certbot-dns-route53

These are used to obtain and manage Let's Encrypt certificates automatically using AWS Route53.

### 📦 Volumes
```
VOLUME [ "/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/sites/assets", "/home/frappe/frappe-bench/logs" ]
```
- sites: Contains per-site configurations and data.
- assets: Public assets.
- logs: Application logs.

Mount these on the host or in a volume to persist data.

### 🚀 Entrypoint (CMD)
Runs the app via gunicorn with production settings:
```
CMD [
  "/home/frappe/frappe-bench/env/bin/gunicorn",
  "--chdir=/home/frappe/frappe-bench/sites",
  "--bind=0.0.0.0:8000",
  "--threads=4",
  "--workers=2",
  "--worker-class=gthread",
  "--worker-tmp-dir=/dev/shm",
  "--timeout=120",
  "--preload",
  "frappe.app:application"
]
```

### ✅ Minimum Requirements
Ensure your server meets the following:

- Memory: 4 GB minimum (recommended)
- Disk Space: 30 GB minimum (recommended)

### 📂 Multi-Stage Summary
| Stage    | Purpose                                  |
|----------|------------------------------------------|
| base     | Common utilities and runtime setup      |
| builder  | Build-time packages and app init        |
| backend  | Final runtime container with app code   |

### 🔒 Security Note
- Uses frappe non-root user for safer execution.
- docker.io is available, but running Docker inside Docker (DinD) should be controlled securely.
