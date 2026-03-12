#!/bin/bash
# =============================================================================
# Script de provisionnement automatique de la VM Azure (Custom Data)
# Ce script est exécuté au premier démarrage de la VM
# =============================================================================

set -e
exec > /var/log/user-data.log 2>&1

echo "========================================="
echo "  Début du provisionnement de la VM"
echo "========================================="

# ---- Variables d'environnement (injectées par Terraform) ----
export AZURE_STORAGE_ACCOUNT="${storage_account_name}"
export AZURE_STORAGE_KEY="${storage_account_key}"
export AZURE_STORAGE_CONTAINER="${storage_container_name}"
export DB_HOST="${db_host}"
export DB_PORT="${db_port}"
export DB_NAME="${db_name}"
export DB_USERNAME="${db_username}"
export DB_PASSWORD="${db_password}"
export APP_PORT="${app_port}"

# ---- Mise à jour du système ----
echo "[1/6] Mise à jour du système..."
apt-get update -y
apt-get upgrade -y

# ---- Installation des dépendances ----
echo "[2/6] Installation de Python et des dépendances..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    postgresql-client \
    curl \
    unzip

# ---- Création du répertoire de l'application ----
echo "[3/6] Configuration de l'application Flask..."
mkdir -p /opt/flask-app
cd /opt/flask-app

# ---- Création de l'environnement virtuel ----
python3 -m venv venv
source venv/bin/activate

# ---- Fichier requirements.txt ----
cat > requirements.txt << 'REQUIREMENTS'
flask==3.0.0
azure-storage-blob==12.19.0
psycopg2-binary>=2.9.9
gunicorn==21.2.0
REQUIREMENTS

pip install --upgrade pip
pip install -r requirements.txt

# ---- Création de l'application Flask ----
cat > app.py << 'FLASK_APP'
"""
Application Flask - Cloud EFREI (Azure)
Backend connecté à Azure Blob Storage et PostgreSQL
"""

import os
import json
from datetime import datetime
from flask import Flask, request, jsonify, send_file
from azure.storage.blob import BlobServiceClient, ContentSettings
import psycopg2
from psycopg2.extras import RealDictCursor
import io

app = Flask(__name__)

# ---- Configuration ----
AZURE_STORAGE_ACCOUNT = os.environ.get("AZURE_STORAGE_ACCOUNT", "cloudefreistorage")
AZURE_STORAGE_KEY = os.environ.get("AZURE_STORAGE_KEY", "")
AZURE_CONTAINER = os.environ.get("AZURE_STORAGE_CONTAINER", "staticfiles")

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": os.environ.get("DB_PORT", "5432"),
    "dbname": os.environ.get("DB_NAME", "flaskdb"),
    "user": os.environ.get("DB_USERNAME", "flaskadmin"),
    "password": os.environ.get("DB_PASSWORD", "password"),
    "sslmode": "require",
}

# ---- Client Azure Blob Storage ----
connection_string = (
    f"DefaultEndpointsProtocol=https;"
    f"AccountName={AZURE_STORAGE_ACCOUNT};"
    f"AccountKey={AZURE_STORAGE_KEY};"
    f"EndpointSuffix=core.windows.net"
)
blob_service_client = BlobServiceClient.from_connection_string(connection_string)
container_client = blob_service_client.get_container_client(AZURE_CONTAINER)


# =============================================================================
# Utilitaires Base de Données
# =============================================================================

def get_db_connection():
    """Créer une connexion à la base de données PostgreSQL."""
    conn = psycopg2.connect(**DB_CONFIG)
    return conn


def init_database():
    """Initialiser la table 'items' dans la base de données."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                description TEXT,
                file_url VARCHAR(500),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        print("[OK] Table 'items' initialisée avec succès.")
    except Exception as e:
        print(f"[ERREUR] Initialisation de la base de données : {e}")


# =============================================================================
# Routes - Page d'accueil
# =============================================================================

@app.route("/")
def index():
    """Page d'accueil - Health check."""
    return jsonify({
        "status": "ok",
        "message": "Bienvenue sur l'API Cloud EFREI (Azure) !",
        "version": "1.0.0",
        "endpoints": {
            "fichiers": {
                "GET /files": "Lister les fichiers dans Azure Blob Storage",
                "POST /files/upload": "Uploader un fichier",
                "GET /files/<filename>": "Télécharger un fichier",
                "DELETE /files/<filename>": "Supprimer un fichier",
            },
            "items_crud": {
                "GET /db/items": "Lister tous les items",
                "POST /db/items": "Créer un item",
                "GET /db/items/<id>": "Récupérer un item",
                "PUT /db/items/<id>": "Mettre à jour un item",
                "DELETE /db/items/<id>": "Supprimer un item",
            },
        },
        "timestamp": datetime.utcnow().isoformat(),
    })


@app.route("/health")
def health():
    """Health check endpoint."""
    health_status = {"api": "ok", "storage": "unknown", "database": "unknown"}

    # Vérifier Azure Blob Storage
    try:
        container_client.get_container_properties()
        health_status["storage"] = "ok"
    except Exception:
        health_status["storage"] = "erreur"

    # Vérifier la base de données
    try:
        conn = get_db_connection()
        conn.close()
        health_status["database"] = "ok"
    except Exception:
        health_status["database"] = "erreur"

    return jsonify(health_status)


# =============================================================================
# Routes - Fichiers Azure Blob Storage (CRUD Stockage)
# =============================================================================

@app.route("/files", methods=["GET"])
def list_files():
    """Lister tous les fichiers dans le conteneur Azure Blob Storage."""
    try:
        prefix = request.args.get("prefix", "")
        blobs = container_client.list_blobs(name_starts_with=prefix if prefix else None)

        files = []
        for blob in blobs:
            files.append({
                "name": blob.name,
                "size": blob.size,
                "last_modified": blob.last_modified.isoformat() if blob.last_modified else None,
                "content_type": blob.content_settings.content_type if blob.content_settings else None,
            })

        return jsonify({
            "container": AZURE_CONTAINER,
            "storage_account": AZURE_STORAGE_ACCOUNT,
            "count": len(files),
            "files": files,
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/files/upload", methods=["POST"])
def upload_file():
    """Uploader un fichier dans Azure Blob Storage."""
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "Nom de fichier vide"}), 400

    # Dossier de destination (images, logs, static)
    folder = request.form.get("folder", "static")
    blob_name = f"{folder}/{file.filename}"

    try:
        blob_client = container_client.get_blob_client(blob_name)
        content_settings = ContentSettings(content_type=file.content_type)
        blob_client.upload_blob(
            file.read(),
            overwrite=True,
            content_settings=content_settings,
        )
        return jsonify({
            "message": "Fichier uploadé avec succès",
            "blob_name": blob_name,
            "container": AZURE_CONTAINER,
        }), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/files/<path:filename>", methods=["GET"])
def download_file(filename):
    """Télécharger un fichier depuis Azure Blob Storage."""
    try:
        blob_client = container_client.get_blob_client(filename)
        blob_data = blob_client.download_blob()
        properties = blob_client.get_blob_properties()
        content_type = properties.content_settings.content_type or "application/octet-stream"

        return send_file(
            io.BytesIO(blob_data.readall()),
            download_name=filename.split("/")[-1],
            mimetype=content_type,
        )
    except Exception as e:
        error_msg = str(e)
        if "BlobNotFound" in error_msg:
            return jsonify({"error": "Fichier non trouvé"}), 404
        return jsonify({"error": error_msg}), 500


@app.route("/files/<path:filename>", methods=["DELETE"])
def delete_file(filename):
    """Supprimer un fichier d'Azure Blob Storage."""
    try:
        blob_client = container_client.get_blob_client(filename)
        blob_client.delete_blob()
        return jsonify({
            "message": f"Fichier '{filename}' supprimé avec succès",
        })
    except Exception as e:
        error_msg = str(e)
        if "BlobNotFound" in error_msg:
            return jsonify({"error": "Fichier non trouvé"}), 404
        return jsonify({"error": error_msg}), 500


# =============================================================================
# Routes - CRUD Base de Données (Items)
# =============================================================================

@app.route("/db/items", methods=["GET"])
def get_items():
    """Lister tous les items."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM items ORDER BY created_at DESC")
        items = cursor.fetchall()
        cursor.close()
        conn.close()

        for item in items:
            item["created_at"] = item["created_at"].isoformat()
            item["updated_at"] = item["updated_at"].isoformat()

        return jsonify({"count": len(items), "items": items})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/db/items", methods=["POST"])
def create_item():
    """Créer un nouvel item."""
    data = request.get_json()
    if not data or "name" not in data:
        return jsonify({"error": "Le champ 'name' est requis"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            INSERT INTO items (name, description, file_url)
            VALUES (%s, %s, %s) RETURNING *
            """,
            (data["name"], data.get("description", ""), data.get("file_url", "")),
        )
        item = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        item["created_at"] = item["created_at"].isoformat()
        item["updated_at"] = item["updated_at"].isoformat()

        return jsonify({"message": "Item créé avec succès", "item": item}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/db/items/<int:item_id>", methods=["GET"])
def get_item(item_id):
    """Récupérer un item par son ID."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute("SELECT * FROM items WHERE id = %s", (item_id,))
        item = cursor.fetchone()
        cursor.close()
        conn.close()

        if item is None:
            return jsonify({"error": "Item non trouvé"}), 404

        item["created_at"] = item["created_at"].isoformat()
        item["updated_at"] = item["updated_at"].isoformat()

        return jsonify(item)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/db/items/<int:item_id>", methods=["PUT"])
def update_item(item_id):
    """Mettre à jour un item."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Aucune donnée fournie"}), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            UPDATE items
            SET name = COALESCE(%s, name),
                description = COALESCE(%s, description),
                file_url = COALESCE(%s, file_url),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s RETURNING *
            """,
            (data.get("name"), data.get("description"), data.get("file_url"), item_id),
        )
        item = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        if item is None:
            return jsonify({"error": "Item non trouvé"}), 404

        item["created_at"] = item["created_at"].isoformat()
        item["updated_at"] = item["updated_at"].isoformat()

        return jsonify({"message": "Item mis à jour avec succès", "item": item})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/db/items/<int:item_id>", methods=["DELETE"])
def delete_item(item_id):
    """Supprimer un item."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("DELETE FROM items WHERE id = %s RETURNING id", (item_id,))
        deleted = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()

        if deleted is None:
            return jsonify({"error": "Item non trouvé"}), 404

        return jsonify({"message": f"Item {item_id} supprimé avec succès"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Démarrage de l'application
# =============================================================================

if __name__ == "__main__":
    print("Initialisation de la base de données...")
    init_database()
    print(f"Démarrage du serveur Flask sur le port {os.environ.get('APP_PORT', 5000)}...")
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("APP_PORT", 5000)),
        debug=False,
    )
FLASK_APP

# ---- Configuration du service systemd ----
echo "[4/6] Configuration du service systemd..."
cat > /etc/systemd/system/flask-app.service << SYSTEMD_SERVICE
[Unit]
Description=Flask Cloud EFREI Application (Azure)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/flask-app
Environment=AZURE_STORAGE_ACCOUNT=${storage_account_name}
Environment=AZURE_STORAGE_KEY=${storage_account_key}
Environment=AZURE_STORAGE_CONTAINER=${storage_container_name}
Environment=DB_HOST=${db_host}
Environment=DB_PORT=${db_port}
Environment=DB_NAME=${db_name}
Environment=DB_USERNAME=${db_username}
Environment=DB_PASSWORD=${db_password}
Environment=APP_PORT=${app_port}
ExecStart=/opt/flask-app/venv/bin/gunicorn --bind 0.0.0.0:${app_port} --workers 2 --timeout 120 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

# ---- Démarrage du service ----
echo "[5/6] Démarrage de l'application Flask..."
systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app

# ---- Initialisation de la base de données ----
echo "[6/6] Initialisation de la base de données..."
sleep 5
cd /opt/flask-app
source venv/bin/activate
python3 -c "
import psycopg2
conn = psycopg2.connect(
    host='${db_host}',
    port='${db_port}',
    dbname='${db_name}',
    user='${db_username}',
    password='${db_password}',
    sslmode='require'
)
cursor = conn.cursor()
cursor.execute('''
    CREATE TABLE IF NOT EXISTS items (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        file_url VARCHAR(500),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
''')
conn.commit()
cursor.close()
conn.close()
print('[OK] Base de données initialisée.')
"

echo "========================================="
echo "  Provisionnement terminé avec succès !"
echo "  Application accessible sur le port ${app_port}"
echo "========================================="
