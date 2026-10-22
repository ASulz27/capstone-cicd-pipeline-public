import os
from flask import Flask, jsonify

app = Flask(__name__)
version = os.environ.get("APP_VERSION", "v1")

@app.route("/")
def index():
    return jsonify({"message": f"Hello from the pipeline!", "version": version})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

    