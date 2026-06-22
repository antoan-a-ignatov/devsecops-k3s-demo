from flask import Flask, jsonify
import psycopg2
import os

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db"),
        database=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "appuser"),
        password=os.environ.get("DB_PASSWORD")
    )

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/data")
def data():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT NOW();")
    result = cur.fetchone()
    cur.close()
    conn.close()
    return jsonify({"db_time": str(result[0])}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
