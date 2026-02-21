locals {
  cloud_init_db_primary = base64encode(templatefile("${path.module}/scripts/cloud_init_db_primary.sh", {
    db_password = var.db_admin_password
    replica_ip  = "10.0.2.11"
  }))

  # Replica disabled due to vCPU quota limit (10 cores max on this subscription).
  # Re-enable after requesting a quota increase at:
  # https://aka.ms/ProdportalCRP/#blade/Microsoft_Azure_Capacity/UsageAndQuota.ReactView
  # cloud_init_db_replica = base64encode(templatefile("${path.module}/scripts/cloud_init_db_replica.sh", {
  #   primary_ip  = "10.0.2.10"
  #   db_password = var.db_admin_password
  # }))
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

# ── NIC: DB Replica (DISABLED – vCPU quota) ───────────────────────────────────
# resource "azurerm_network_interface" "db_replica" {
#   name                = "db-vm-replica-nic"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#
#   ip_configuration {
#     name                          = "ipconfig"
#     subnet_id                     = azurerm_subnet.db.id
#     private_ip_address_allocation = "Static"
#     private_ip_address            = "10.0.2.11"
#   }
# }

# ── VM: DB Primary (Zone 1) ───────────────────────────────────────────────────
# PostgreSQL primary – accepts reads and writes from app VMs.
resource "azurerm_linux_virtual_machine" "db_primary" {
  name                = "db-vm-primary"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

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

# ── VM: DB Replica (DISABLED – vCPU quota limit) ─────────────────────────────
# To re-enable: request a quota increase (need limit >= 12 cores in East US 2),
# uncomment this block and the db_replica NIC above, then push to trigger apply.
#
# resource "azurerm_linux_virtual_machine" "db_replica" {
#   name                = "db-vm-replica"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   size                = var.vm_size
#   admin_username      = var.admin_username
#   admin_password      = var.admin_password
#
#   disable_password_authentication = false
#
#   network_interface_ids = [azurerm_network_interface.db_replica.id]
#
#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Premium_LRS"
#   }
#
#   source_image_reference {
#     publisher = "Canonical"
#     offer     = "0001-com-ubuntu-server-jammy"
#     sku       = "22_04-lts-gen2"
#     version   = "latest"
#   }
#
#   custom_data = local.cloud_init_db_replica
#
#   depends_on = [azurerm_linux_virtual_machine.db_primary]
#
#   tags = {
#     role = "db-replica"
#   }
# }
