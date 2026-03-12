# =============================================================================
# Variables Terraform - Azure
# =============================================================================

# ---- Général ----
variable "project_name" {
  description = "Nom du projet, utilisé pour nommer les ressources"
  type        = string
  default     = "cloud-efrei"
}

variable "location" {
  description = "Région Azure pour le déploiement"
  type        = string
  default     = "France Central"
}

# ---- Réseau ----
variable "vnet_address_space" {
  description = "Espace d'adressage du VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Préfixes d'adresse du sous-réseau"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# ---- Machine Virtuelle ----
variable "vm_size" {
  description = "Taille de la VM Azure"
  type        = string
  default     = "Standard_B2ls_v2"
}

variable "admin_username" {
  description = "Nom d'utilisateur administrateur de la VM"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Mot de passe administrateur de la VM"
  type        = string
  sensitive   = true
}

# ---- Stockage ----
variable "storage_account_name" {
  description = "Nom du compte de stockage Azure (3-24 caractères, minuscules et chiffres uniquement)"
  type        = string
}

variable "storage_container_name" {
  description = "Nom du conteneur de stockage blob"
  type        = string
  default     = "staticfiles"
}

# ---- Base de données PostgreSQL ----
variable "db_admin_username" {
  description = "Nom d'utilisateur admin PostgreSQL"
  type        = string
  default     = "flaskadmin"
  sensitive   = true
}

variable "db_admin_password" {
  description = "Mot de passe admin PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
  default     = "flaskdb"
}

# ---- Application ----
variable "app_port" {
  description = "Port sur lequel l'application Flask écoute"
  type        = number
  default     = 5000
}
