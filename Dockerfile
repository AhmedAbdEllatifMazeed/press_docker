ARG PYTHON_VERSION=3.11.6
ARG DEBIAN_BASE=bookworm
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

# Copy templates and entrypoint
COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh

# Docker and other build args
ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm
ARG NODE_VERSION=18.18.2
ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        curl git vim nginx gettext-base file \
        libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
        restic gpg mariadb-client less libpq-dev postgresql-client \
        wait-for-it jq wget docker.io \
    # Allow frappe user to run Docker without sudo
    && groupadd -f docker \
    && usermod -aG docker frappe \
    # NodeJS via NVM
    && mkdir -p ${NVM_DIR} \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use v${NODE_VERSION} \
    && npm install -g yarn \
    && nvm alias default v${NODE_VERSION} \
    && rm -rf ${NVM_DIR}/.cache \
    && echo 'export NVM_DIR="/home/frappe/.nvm"' >>/home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >>/home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >>/home/frappe/.bashrc \
    # Install wkhtmltopdf
    && if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi \
    && if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi \
    && downloaded_file=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
    && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/$WKHTMLTOPDF_VERSION/$downloaded_file \
    && apt-get install -y ./$downloaded_file \
    && rm $downloaded_file \
    && rm -rf /var/lib/apt/lists/* \
    && rm -fr /etc/nginx/sites-enabled/default \
    && pip3 install frappe-bench \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe /etc/nginx/conf.d /etc/nginx/nginx.conf /var/log/nginx /var/lib/nginx /run/nginx.pid \
    && chmod 755 /usr/local/bin/nginx-entrypoint.sh \
    && chmod 644 /templates/nginx/frappe.conf.template

FROM base AS builder

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev \
        libpq-dev libffi-dev liblcms2-dev libldap2-dev libmariadb-dev libsasl2-dev \
        libtiff5-dev libwebp-dev pkg-config redis-tools rlwrap tk8.6-dev cron \
        gcc build-essential libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

# apps.json support
ARG APPS_JSON_BASE64
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
    mkdir /opt/frappe && echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; \
  fi

USER frappe
ARG FRAPPE_BRANCH=version-15
ARG FRAPPE_PATH=https://github.com/frappe/frappe
RUN export APP_INSTALL_ARGS="" \
    && if [ -n "${APPS_JSON_BASE64}" ]; then export APP_INSTALL_ARGS="--apps_path=/opt/frappe/apps.json"; fi \
    && bench init ${APP_INSTALL_ARGS} --frappe-branch=${FRAPPE_BRANCH} --frappe-path=${FRAPPE_PATH} \
        --no-procfile --no-backups --skip-redis-config-generation --verbose /home/frappe/frappe-bench \
    && cd /home/frappe/frappe-bench \
    && echo "{}" > sites/common_site_config.json \
    && find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM base AS backend
USER frappe

# Copy bench from builder
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

# Create directories for certbot and local builds/clones
RUN mkdir -p /home/frappe/.certbot/webroot \
    && mkdir -p /home/frappe/frappe-bench/.clones \
    && mkdir -p /home/frappe/frappe-bench/.docker-builds \
    && chown -R frappe:frappe /home/frappe/.certbot /home/frappe/frappe-bench/.clones /home/frappe/frappe-bench/.docker-builds

# Install certbot and DNS plugin inside the bench venv
RUN /home/frappe/frappe-bench/env/bin/pip install --upgrade certbot \
    && /home/frappe/frappe-bench/env/bin/pip install certbot-dns-route53

WORKDIR /home/frappe/frappe-bench
VOLUME [ "/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/sites/assets", "/home/frappe/frappe-bench/logs" ]

CMD [ \
  "/home/frappe/frappe-bench/env/bin/gunicorn", \
  "--chdir=/home/frappe/frappe-bench/sites", \
  "--bind=0.0.0.0:8000", \
  "--threads=4", \
  "--workers=2", \
  "--worker-class=gthread", \
  "--worker-tmp-dir=/dev/shm", \
  "--timeout=120", \
  "--preload", \
  "frappe.app:application" \
]