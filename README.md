# ☁️ Cloud EFREI — Infrastructure Terraform + Flask sur Azure

Déploiement automatisé d'une infrastructure cloud complète sur **Azure** avec **Terraform** :
- **Machine virtuelle Linux** (Ubuntu 24.04) avec une application **Flask**
- **Azure Blob Storage** pour les fichiers statiques (images, logs, etc.)
- **Azure Database for PostgreSQL** (Flexible Server) managé
- **Provisionnement automatique** via custom-data (systemd)

---

## 📁 Structure du Projet

```
Cloud/
├── terraform/                   # Fichiers Terraform
│   ├── provider.tf              # Configuration du provider Azure
│   ├── variables.tf             # Variables d'entrée
│   ├── main.tf                  # Ressources Azure (RG, VNet, NSG, VM, Storage, PostgreSQL)
│   ├── outputs.tf               # Sorties (IP, URL, endpoints)
│   ├── user_data.sh             # Script de provisionnement de la VM
│   ├── terraform.tfvars.example # Exemple de fichier de variables
│   └── terraform.tfvars         # Valeurs réelles (à créer, non versionné)
├── app/                         # Application Flask (développement local)
│   ├── app.py                   # Code source du backend
│   └── requirements.txt         # Dépendances Python
├── .gitignore
└── README.md
```

---

## 🏗️ Architecture

```
                    ┌──────────────────────────────────────────┐
                    │         Azure Cloud (France Central)      │
                    │                                          │
                    │  ┌──── Resource Group (cloud-efrei-rg) ─┐│
                    │  │                                      ││
                    │  │  ┌──────── VNet (10.0.0.0/16) ─────┐ ││
                    │  │  │                                  │ ││
                    │  │  │  ┌───────────────────────────┐   │ ││
                    │  │  │  │ Subnet Public (10.0.1.0)  │   │ ││
                    │  │  │  │                           │   │ ││
 Utilisateur ──────┼──┼──┼──│──► VM Linux (Flask)       │   │ ││
     :5000         │  │  │  │   Ubuntu 24.04 / B2ls    │   │ ││
                    │  │  │  └────────┬──────────────────┘   │ ││
                    │  │  │           │                       │ ││
                    │  │  │  ┌────────▼──────────────────┐   │ ││
                    │  │  │  │ Subnet DB (10.0.2.0)      │   │ ││
                    │  │  │  │ PostgreSQL Flexible Server │   │ ││
                    │  │  │  │ B_Standard_B1ms            │   │ ││
                    │  │  │  └───────────────────────────┘   │ ││
                    │  │  └──────────────────────────────────┘ ││
                    │  │                                       ││
                    │  │  ┌──────────────────────────┐         ││
                    │  │  │  Storage Account           │         ││
                    │  │  │  └── Container: staticfiles│         ││
                    │  │  │      ├── images/           │         ││
                    │  │  │      ├── logs/             │         ││
                    │  │  │      └── static/           │         ││
                    │  │  └──────────────────────────┘         ││
                    │  └───────────────────────────────────────┘│
                    └──────────────────────────────────────────┘
```

---

## ✅ Prérequis

1. **Terraform** ≥ 1.0 — [Installation](https://developer.hashicorp.com/terraform/install)
2. **Azure CLI** — [Installation](https://docs.microsoft.com/fr-fr/cli/azure/install-azure-cli)
3. **Compte Azure** avec un abonnement actif

### Se connecter à Azure

```bash
az login
```

### Vérifier l'abonnement actif

```bash
az account show
```

---

## 🚀 Étape 1 : Déployer l'Infrastructure

### 1.1. Configurer les variables

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Modifier `terraform.tfvars` avec vos valeurs :

```hcl
location             = "France Central"
project_name         = "cloud-efrei"
vm_size              = "Standard_B2ls_v2"
admin_username       = "azureuser"
admin_password       = "VotreMotDePasse@Securise123!"
storage_account_name = "cloudefreistorageXXXX"   # Unique, minuscules+chiffres
db_admin_username    = "flaskadmin"
db_admin_password    = "PostgreSQL@Securise123!"
db_name              = "flaskdb"
app_port             = 5000
```

> ⚠️ Le `storage_account_name` doit être globalement unique, 3-24 caractères, minuscules et chiffres uniquement.

### 1.2. Initialiser Terraform

```bash
terraform init
```

### 1.3. Prévisualiser les ressources

```bash
terraform plan
```

### 1.4. Déployer

```bash
terraform apply
```

Tapez `yes` pour confirmer. Le déploiement prend environ **10-15 minutes** (PostgreSQL Flexible Server prend le plus de temps).

### 1.5. Récupérer les informations

```bash
terraform output
```

Résultat attendu :
```
app_url                = "http://XX.XX.XX.XX:5000"
vm_public_ip           = "XX.XX.XX.XX"
storage_account_name   = "cloudefreistorageXXXX"
postgresql_fqdn        = "cloud-efrei-psql.postgres.database.azure.com"
ssh_command            = "ssh azureuser@XX.XX.XX.XX"
```

---

## 🔌 Étape 2 : Tester l'API

> **Note** : Attendre 2-3 minutes après le déploiement pour que le provisionnement de la VM soit terminé.

### 2.1. Health Check

```bash
curl http://<IP_PUBLIQUE>:5000/
curl http://<IP_PUBLIQUE>:5000/health
```

### 2.2. Opérations sur les fichiers (Azure Blob Storage)

**Lister les fichiers :**
```bash
curl http://<IP_PUBLIQUE>:5000/files
```

**Uploader un fichier :**
```bash
curl -X POST http://<IP_PUBLIQUE>:5000/files/upload \
  -F "file=@mon_image.png" \
  -F "folder=images"
```

**Télécharger un fichier :**
```bash
curl http://<IP_PUBLIQUE>:5000/files/images/mon_image.png --output mon_image.png
```

**Supprimer un fichier :**
```bash
curl -X DELETE http://<IP_PUBLIQUE>:5000/files/images/mon_image.png
```

### 2.3. Opérations CRUD sur la Base de Données

**Créer un item :**
```bash
curl -X POST http://<IP_PUBLIQUE>:5000/db/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Logo EFREI", "description": "Logo officiel", "file_url": "images/logo.png"}'
```

**Lister tous les items :**
```bash
curl http://<IP_PUBLIQUE>:5000/db/items
```

**Récupérer un item :**
```bash
curl http://<IP_PUBLIQUE>:5000/db/items/1
```

**Mettre à jour un item :**
```bash
curl -X PUT http://<IP_PUBLIQUE>:5000/db/items/1 \
  -H "Content-Type: application/json" \
  -d '{"description": "Logo officiel mis à jour"}'
```

**Supprimer un item :**
```bash
curl -X DELETE http://<IP_PUBLIQUE>:5000/db/items/1
```

---

## 🔧 Étape 3 : Accès SSH à la VM

```bash
ssh azureuser@<IP_PUBLIQUE>
```

Vérifier le status de l'application :
```bash
sudo systemctl status flask-app
```

Consulter les logs :
```bash
sudo journalctl -u flask-app -f
```

Consulter les logs de provisionnement :
```bash
cat /var/log/user-data.log
```

---

## 🗑️ Étape 4 : Détruire l'Infrastructure

```bash
cd terraform/
terraform destroy
```

Tapez `yes` pour confirmer la suppression de toutes les ressources.

---

## 📊 Ressources Créées par Terraform

| Ressource | Type Azure | Description |
|---|---|---|
| Resource Group | `azurerm_resource_group` | Groupe de ressources |
| VNet | `azurerm_virtual_network` | Réseau virtuel (10.0.0.0/16) |
| Subnet Public | `azurerm_subnet` | Sous-réseau VM (10.0.1.0/24) |
| Subnet DB | `azurerm_subnet` | Sous-réseau PostgreSQL (10.0.2.0/24) |
| NSG | `azurerm_network_security_group` | Ports 22, 80, 5000 ouverts |
| IP Publique | `azurerm_public_ip` | IP statique Standard |
| NIC | `azurerm_network_interface` | Interface réseau VM |
| Storage Account | `azurerm_storage_account` | Compte de stockage LRS |
| Blob Container | `azurerm_storage_container` | Conteneur fichiers statiques |
| PostgreSQL | `azurerm_postgresql_flexible_server` | PostgreSQL 15 (B1ms) |
| VM Linux | `azurerm_linux_virtual_machine` | Ubuntu 24.04 (B2ls_v2) |

---

## 💡 Technologies Utilisées

- **Terraform** — Infrastructure as Code
- **Azure** — Cloud Provider (VM, Blob Storage, PostgreSQL, VNet, NSG)
- **Flask** — Framework backend Python
- **Gunicorn** — Serveur WSGI de production
- **PostgreSQL** — Base de données relationnelle
- **azure-storage-blob** — SDK Azure pour Python
- **systemd** — Gestion du service Flask sur la VM

---

## ⚠️ Notes Importantes

- Le fichier `terraform.tfvars` contient des informations sensibles et **ne doit pas** être versionné (il est dans le `.gitignore`)
- Le `storage_account_name` doit être **globalement unique** (3-24 caractères, minuscules et chiffres)
- Les mots de passe Azure doivent respecter les exigences de complexité (majuscule, minuscule, chiffre, caractère spécial)
- La VM `Standard_B1s` est éligible au **Free Tier Azure** (750h/mois la première année)
- Pensez à exécuter `terraform destroy` pour éviter les coûts inutiles
