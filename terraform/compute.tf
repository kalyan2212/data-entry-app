locals {
  # Map of app VM names → their static private IPs
  app_vms = {
    "app-vm-1" = { private_ip = "10.0.1.10" }
    "app-vm-2" = { private_ip = "10.0.1.11" }
  }

  # Cloud-init script, rendered with secrets and passed as base64 custom_data
  cloud_init_app = base64encode(templatefile("${path.module}/scripts/cloud_init_app.sh", {
    db_host            = "10.0.2.10"
    db_port            = "5432"
    db_name            = "customers"
    db_user            = "appuser"
    db_password        = var.db_admin_password
    flask_secret_key   = var.app_secret_key
    upstream_api_key   = var.upstream_api_key
    downstream_api_key = var.downstream_api_key
    github_repo        = var.github_repo
  }))
}

# ── Network Interfaces (no public IP – behind LB) ────────────────────────────
resource "azurerm_network_interface" "app" {
  for_each            = local.app_vms
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

# ── Attach NICs to LB backend pool ───────────────────────────────────────────
resource "azurerm_network_interface_backend_address_pool_association" "app" {
  for_each                = local.app_vms
  network_interface_id    = azurerm_network_interface.app[each.key].id
  ip_configuration_name   = "ipconfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id
}

# ── App Linux VMs (Zone 1) ────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "app" {
  for_each            = local.app_vms
  name                = each.key
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  zone                = "1"

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.app[each.key].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # cloud-init runs on first boot: installs Python, Nginx, clones repo, starts app
  custom_data = local.cloud_init_app

  tags = {
    role = "app"
  }
}
