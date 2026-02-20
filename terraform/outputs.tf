output "load_balancer_public_ip" {
  description = "Public IP of the Load Balancer – access the app at http://<this IP>/"
  value       = azurerm_public_ip.lb.ip_address
}

output "app_vm_1_private_ip" {
  description = "Private IP of app-vm-1"
  value       = azurerm_network_interface.app["app-vm-1"].private_ip_address
}

output "app_vm_2_private_ip" {
  description = "Private IP of app-vm-2"
  value       = azurerm_network_interface.app["app-vm-2"].private_ip_address
}

output "db_primary_private_ip" {
  description = "Private IP of the PostgreSQL primary VM (app VMs connect here)"
  value       = azurerm_network_interface.db_primary.private_ip_address
}

output "db_replica_private_ip" {
  description = "Private IP of the PostgreSQL replica VM (hot standby)"
  value       = azurerm_network_interface.db_replica.private_ip_address
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}
