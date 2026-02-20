# ── Azure Load Balancer (Standard, Zone 1) ────────────────────────────────────
resource "azurerm_lb" "main" {
  name                = "data-entry-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

# ── Backend Pool (app VMs join this) ──────────────────────────────────────────
resource "azurerm_lb_backend_address_pool" "app" {
  name            = "app-backend-pool"
  loadbalancer_id = azurerm_lb.main.id
}

# ── Health Probe: HTTP GET / on port 80 ───────────────────────────────────────
resource "azurerm_lb_probe" "http" {
  name            = "http-health-probe"
  loadbalancer_id = azurerm_lb.main.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# ── Load Balancing Rule: port 80 → app VMs port 80 ───────────────────────────
resource "azurerm_lb_rule" "http" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.http.id
  disable_outbound_snat          = true
  idle_timeout_in_minutes        = 4
}

# ── Outbound Rule: allows VMs to reach the internet (to run apt-get, git clone)
resource "azurerm_lb_outbound_rule" "app" {
  name                    = "app-outbound"
  loadbalancer_id         = azurerm_lb.main.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id

  frontend_ip_configuration {
    name = "frontend"
  }

  allocated_outbound_ports = 1024
}
