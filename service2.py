from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route("/banned-alert", methods=["POST"])
def banned_alert():
    data = request.get_json(silent=True) or {}
    country = data.get("country", "Unknown")
    file_target = data.get("file", "Unknown")
    client_ip = data.get("client_ip", "Unknown")
    
    print(f"[SECURITY ALERT] Prohibited export attempt detected from {country} | Client IP: {client_ip} | Target: {file_target}", flush=True)
    return jsonify({"status": "logged"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
