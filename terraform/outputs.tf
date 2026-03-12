# =============================================================================
# Outputs Terraform - Azure
# =============================================================================

# ---- VM ----
output "vm_public_ip" {
  description = "Adresse IP publique de la machine virtuelle"
  value       = azurerm_public_ip.main.ip_address
}

output "app_url" {
  description = "URL de l'application Flask"
  value       = "http://${azurerm_public_ip.main.ip_address}:${var.app_port}"
}

# ---- Stockage ----
output "storage_account_name" {
  description = "Nom du compte de stockage Azure"
  value       = azurerm_storage_account.main.name
}

output "storage_container_name" {
  description = "Nom du conteneur de stockage blob"
  value       = azurerm_storage_container.static_files.name
}

output "storage_primary_endpoint" {
  description = "Endpoint principal du stockage blob"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# ---- Base de données ----
output "postgresql_fqdn" {
  description = "FQDN du serveur PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgresql_server_name" {
  description = "Nom du serveur PostgreSQL"
  value       = azurerm_postgresql_flexible_server.main.name
}

# ---- Resource Group ----
output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = azurerm_resource_group.main.name
}

# ---- Connexion SSH ----
output "ssh_command" {
  description = "Commande SSH pour se connecter à la VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}
