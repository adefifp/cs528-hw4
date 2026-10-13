import mimetypes
import requests
from flask import Flask, request, Response
from google.cloud import storage
from google.cloud import logging as cloud_logging
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

logging_client = cloud_logging.Client()
logger = logging_client.logger("storage-web-server")

def log_structured(severity, message, extra=None):
    payload = {
        "component": "storage-web-server",
        "message": message
    }
    if extra:
        payload.update(extra)
    logger.log_struct(payload, severity=severity)
    print(f"[{severity}] {message}", flush=True)

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
        content_type, _ = mimetypes.guess_type(filename)
        if not content_type:
            content_type = "text/html" if filename.endswith(".html") else "application/octet-stream"
        return Response(content, status=200, mimetype=content_type)
    except NotFound:
        log_structured("WARNING", f"File not found: {filename}", {"filename": filename})
        return Response(f"Error 404: File \"{filename}\" not found", status=404, mimetype="text/html")
    except Exception as e:
        log_structured("ERROR", f"Internal error retrieving file: {str(e)}")
        return Response("Internal server error", status=500, mimetype="text/html")

@app.route("/<path:filename>", methods=["GET"])
def handle_get(filename):
    return fetch_file(filename)

@app.route("/", methods=["POST"])
def handle_post():
    data = request.get_json(silent=True) or {}
    filename = data.get("filename") or request.form.get("filename")
    if not filename:
        return Response("Missing filename in POST body", status=400, mimetype="text/html")
    return fetch_file(filename)

@app.route("/", defaults={"path": ""}, methods=["PUT", "DELETE", "HEAD", "CONNECT", "OPTIONS", "TRACE", "PATCH"])
@app.route("/<path:path>", methods=["PUT", "DELETE", "HEAD", "CONNECT", "OPTIONS", "TRACE", "PATCH"])
def handle_unimplemented(path):
    log_structured("ERROR", f"Unsupported HTTP method: {request.method}", {"method": request.method, "path": path})
    return Response(f"Method {request.method} Not Implemented", status=501, mimetype="text/html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
