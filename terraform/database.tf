locals {
  cloud_init_db_primary = base64encode(templatefile("${path.module}/scripts/cloud_init_db_primary.sh", {
    db_password = var.db_admin_password
    replica_ip  = "10.0.2.11"
  }))

  cloud_init_db_replica = base64encode(templatefile("${path.module}/scripts/cloud_init_db_replica.sh", {
    primary_ip  = "10.0.2.10"
    db_password = var.db_admin_password
  }))
}

# ── NIC: DB Primary (static private IP 10.0.2.10) ─────────────────────────────
resource "azurerm_network_interface" "db_primary" {
  name                = "db-vm-primary-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
  }
}

# ── NIC: DB Replica (static private IP 10.0.2.11) ────────────────────────────
resource "azurerm_network_interface" "db_replica" {
  name                = "db-vm-replica-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.11"
  }
}

# ── VM: DB Primary (Zone 1) ───────────────────────────────────────────────────
# PostgreSQL primary – accepts reads and writes from app VMs.
resource "azurerm_linux_virtual_machine" "db_primary" {
  name                = "db-vm-primary"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  zone                = "1"

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.db_primary.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"   # Premium for DB I/O
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = local.cloud_init_db_primary

  tags = {
    role = "db-primary"
  }
}

# ── VM: DB Replica (Zone 1) ───────────────────────────────────────────────────
# PostgreSQL hot-standby replica – streams WAL from primary.
# Promote manually if the primary fails.
resource "azurerm_linux_virtual_machine" "db_replica" {
  name                = "db-vm-replica"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  zone                = "1"

  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.db_replica.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = local.cloud_init_db_replica

  # Replica script connects to the primary, so primary must exist first
  depends_on = [azurerm_linux_virtual_machine.db_primary]

  tags = {
    role = "db-replica"
  }
}
