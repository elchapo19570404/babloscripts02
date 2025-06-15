#!/bin/bash

# Customize Nmap scan flags
NMAP_FLAGS=${1:--Pn -sS -p 80,443,8080,8000,8443}
TIMESTAMP=$(date +%F_%T)
LOG_DIR="k8s_scan_$TIMESTAMP"
mkdir -p "$LOG_DIR"

# Check dependencies
for cmd in kubectl nmap nikto; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "[ERROR] Required command '$cmd' not found. Please install it."
    exit 1
  fi
done

echo "[INFO] Fetching pod IPs from Kubernetes..."

# Get IPs of Running pods
POD_IPS=$(kubectl get pods -A -o jsonpath="{range .items[?(@.status.phase=='Running')]}{.status.podIP}{'\n'}{end}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)

if [ -z "$POD_IPS" ]; then
  echo "[WARN] No running pods with IPs found."
  exit 0
fi

echo "[INFO] Found $(echo "$POD_IPS" | wc -l) pod IPs. Scanning..."

for ip in $POD_IPS; do
  echo -e "\n[INFO] Scanning $ip with Nmap..."
  NMAP_RESULT_FILE="$LOG_DIR/${ip}_nmap.txt"
  nmap $NMAP_FLAGS "$ip" -oN "$NMAP_RESULT_FILE"

  # Check for HTTP/HTTPS ports
  HTTP_PORTS=$(grep -E '^[0-9]+/tcp.*open' "$NMAP_RESULT_FILE" | grep -E 'http|https|www' | cut -d '/' -f 1)

  for port in $HTTP_PORTS; do
    PROTO="http"
    [[ "$port" == "443" || "$port" == "8443" ]] && PROTO="https"
    TARGET="$PROTO://$ip:$port"

    echo "[INFO] Found $PROTO service on $ip:$port. Running Nikto..."
    NIKTO_RESULT_FILE="$LOG_DIR/${ip}_${port}_nikto.txt"
    nikto -host "$TARGET" -output "$NIKTO_RESULT_FILE" -nointeractive
  done
done

echo -e "\n[INFO] Scan complete. All results saved in $LOG_DIR/"
