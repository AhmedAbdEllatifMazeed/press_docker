# Frappe Press Docker

This repository provides a Dockerized setup for deploying a [Frappe Press](https://github.com/frappe/press) app tailored for cloud solutions. It allows you to build and run the app using Docker and Docker Compose.

> 💡 **Note**: Ensure your server is AMD architectrue has at least **4 GB of memory** and **30 GB of disk storage** for optimal performance.

## Features

- Containerized deployment using Docker
- Easy to build and run
- Supports custom app installation via `apps.json`


## Prerequisites

- Linux server AMD architectrue
- 4GB memory
- 30 GB of disk storage
- docker & docker compose cli

---

## How to Run

Follow the steps below to build and run the Frappe Press app:

Run the following command to encode the file:

### 1. Clone `press_docker` repository
```bash
git clone https://github.com/AhmedAbdEllatifMazeed/press_docker.git && cd press_docker
```

### 2. Prepare the `apps.json` file
Create or modify the `apps.json` file with the desired Frappe apps configuration.

### 3. Convert `apps.json` to Base64
```bash
base64 -w0 apps.json > apps.json.base64
```
### 4. Build `frappe-press` docker image
```bash
docker build --build-arg APPS_JSON_BASE64=$(cat apps.json.base64) -t frappe-press:latest .
```
### 5. Run the app with docker compose
```bash
docker-compose up -d
```




