#!/bin/bash
apt-get update
apt-get install -y python3-pip python3-flask python3-requests
pip3 install google-cloud-storage

cat << 'PYEOF' > /opt/server.py
import json
import requests
from flask import Flask, request, Response
from google.cloud import storage
from google.cloud.exceptions import NotFound

app = Flask(__name__)

BUCKET_NAME = "cs528-pagerank-eddielu-1790373540"
SERVICE_2_URL = "http://10.128.0.5:8080/banned-alert"

BANNED_COUNTRIES = {
    "North Korea", "Iran", "Cuba", "Myanmar",
    "Iraq", "Libya", "Sudan", "Zimbabwe", "Syria"
}

storage_client = storage.Client()
bucket = storage_client.bucket(BUCKET_NAME)

def log_structured(severity, message, extra=None):
    payload = {
        "severity": severity,
        "message": message,
        "component": "storage-web-server"
    }
    if extra:
        payload.update(extra)
    print(json.dumps(payload), flush=True)

def check_banned_country(file_target):
    country = request.headers.get("X-Country") or request.headers.get("X-AppEngine-Country")
    if country in BANNED_COUNTRIES:
        log_structured("CRITICAL", f"Banned country request attempt from {country} for file {file_target}", {
            "country": country,
            "file": file_target,
            "ip": request.remote_addr
        })
        try:
            requests.post(SERVICE_2_URL, json={
                "country": country,
                "file": file_target,
                "client_ip": request.remote_addr
            }, timeout=2)
        except Exception as e:
            log_structured("ERROR", f"Failed to notify Service 2: {str(e)}")
        return True, country
    return False, None

def fetch_file(filename):
    banned, country = check_banned_country(filename)
    if banned:
        return Response(f"Forbidden: Export to {country} prohibited", status=403)
        
    try:
        blob = bucket.blob(filename)
        content = blob.download_as_bytes()
        return Response(content, status=200, mimetype="application/octet-stream")
    except NotFound:
        log_structured("WARNING", f"File not found: {filename}", {"filename": filename})
        return Response(f"Error 404: File '{filename}' not found", status=404)
    except Exception as e:
        log_structured("ERROR", f"Internal error retrieving file: {str(e)}")
        return Response("Internal server error", status=500)

@app.route('/<path:filename>', methods=['GET'])
def handle_get(filename):
    return fetch_file(filename)

@app.route('/', methods=['POST'])
def handle_post():
    data = request.get_json(silent=True) or {}
    filename = data.get("filename") or request.form.get("filename")
    if not filename:
        return Response("Missing filename in POST body", status=400)
    return fetch_file(filename)

@app.route('/', defaults={'path': ''}, methods=['PUT', 'DELETE', 'HEAD', 'CONNECT', 'OPTIONS', 'TRACE', 'PATCH'])
@app.route('/<path:path>', methods=['PUT', 'DELETE', 'HEAD', 'CONNECT', 'OPTIONS', 'TRACE', 'PATCH'])
def handle_unimplemented(path):
    log_structured("ERROR", f"Unsupported HTTP method: {request.method}", {"method": request.method, "path": path})
    return Response(f"Method {request.method} Not Implemented", status=501)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
PYEOF

cat << 'SYSEOF' > /etc/systemd/system/webserver.service
[Unit]
Description=Storage Web Server Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/server.py
WorkingDirectory=/opt
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSEOF

systemctl daemon-reload
systemctl enable webserver.service
systemctl start webserver.service
