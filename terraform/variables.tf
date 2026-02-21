variable "subscription_id" {
  description = "Azure Subscription ID (GUID). Set via AZURE_SUBSCRIPTION_ID GitHub Secret."
  type        = string
  default     = "cd682acc-0b1e-46f0-a72f-236d216bd4e1"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group for the application."
  type        = string
  default     = "data-entry"
}

variable "location" {
  description = "Azure region to deploy all resources."
  type        = string
  default     = "East US"
}

variable "vm_size" {
  description = "VM SKU for both app and DB VMs."
  type        = string
  default     = "Standard_B2ms"
}

variable "admin_username" {
  description = "OS admin username for all VMs."
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "OS admin password for all VMs. Set via VM_ADMIN_PASSWORD GitHub Secret."
  type        = string
  sensitive   = true
}

variable "db_admin_password" {
  description = "PostgreSQL password for 'appuser' and 'replicator'. Set via DB_ADMIN_PASSWORD GitHub Secret."
  type        = string
  sensitive   = true
}

variable "app_secret_key" {
  description = "Flask FLASK_SECRET_KEY. Set via APP_SECRET_KEY GitHub Secret."
  type        = string
  sensitive   = true
}

variable "upstream_api_key" {
  description = "API key for the upstream application. Set via UPSTREAM_API_KEY GitHub Secret."
  type        = string
  sensitive   = true
  default     = "upstream-app-key-001"
}

variable "downstream_api_key" {
  description = "API key for the downstream application. Set via DOWNSTREAM_API_KEY GitHub Secret."
  type        = string
  sensitive   = true
  default     = "downstream-app-key-002"
}

variable "github_repo" {
  description = "HTTPS URL of the GitHub repository to clone on app VMs."
  type        = string
  default     = "https://github.com/kalyan2212/data-entry-app.git"  # already correct
}
