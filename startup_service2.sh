#!/bin/bash
apt-get update
apt-get install -y python3-pip python3-flask

cat << "PYEOF" > /opt/service2.py
from flask import Flask, request
import sys

app = Flask(__name__)

@app.route("/banned-alert", methods=["POST"])
def banned_alert():
    data = request.get_json(silent=True) or {}
    country = data.get("country", "Unknown")
    target_file = data.get("file", "Unknown")
    client_ip = data.get("client_ip", "Unknown")
    print(f"[SECURITY ALERT] Prohibited export attempt detected from {country} | Client IP: {client_ip} | Target: {target_file}", file=sys.stdout, flush=True)
    return {"status": "received"}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

cat << "SYSEOF" > /etc/systemd/system/service2.service
[Unit]
Description=Banned Country Tracker Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/service2.py
WorkingDirectory=/opt
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSEOF

systemctl daemon-reload
systemctl enable service2.service
systemctl start service2.service
