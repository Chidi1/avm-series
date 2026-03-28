############################################
# RESOURCE GROUP
############################################
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

############################################
# 1. VNET FOUNDATION
############################################
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"

  name                = "${var.prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  address_space = ["10.0.0.0/16"]

  subnets = {
    aks = { address_prefixes = ["10.0.1.0/24"] }
    app = { address_prefixes = ["10.0.2.0/24"] }
    db  = { address_prefixes = ["10.0.3.0/24"] }
  }
}

############################################
# 2. AKS
############################################
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"

  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks"

  default_node_pool = {
    name       = "system"
    vm_size    = "Standard_DS2_v2"
    node_count = 2
  }

  network_profile = {
    network_plugin = "azure"
  }
}

############################################
# 3. VM
############################################
module "vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"

  name                = "${var.prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  admin_username = var.admin_username
  size           = "Standard_B2s"
}

############################################
# 4. SQL + AUDITING
############################################
module "sql_server" {
  source  = "Azure/avm-res-sql-server/azurerm"

  name                = "${var.prefix}-sql"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  administrator_login          = var.sql_admin
  administrator_login_password = var.sql_password
}

module "sql_db" {
  source = "Azure/avm-res-sql-database/azurerm"

  name      = "${var.prefix}-db"
  server_id = module.sql_server.id
}

resource "azurerm_mssql_server_extended_auditing_policy" "audit" {
  server_id = module.sql_server.id
  enabled   = true
}

############################################
# 5. APP SERVICE
############################################
module "appservice" {
  source = "Azure/avm-res-web-site/azurerm"

  name                = "${var.prefix}-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  https_only = true
}

############################################
# 6. REDIS
############################################
module "redis" {
  source = "Azure/avm-res-cache-redis/azurerm"

  name                = "${var.prefix}-redis"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "Premium"
}

############################################
# 7. PRIVATE AKS + ACR
############################################
module "acr" {
  source = "Azure/avm-res-containerregistry-registry/azurerm"

  name                = "${var.prefix}acr"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku = "Premium"
}

module "aks_private" {
  source = "Azure/avm-res-containerservice-managedcluster/azurerm"

  name                    = "${var.prefix}-aks-private"
  location                = var.location
  resource_group_name     = azurerm_resource_group.rg.name
  private_cluster_enabled = true
  dns_prefix              = "akspriv"
}

############################################
# 8. HUB & SPOKE
############################################
module "hubspoke" {
  source = "Azure/avm-ptn-network-hubspoke/azurerm"

  hub_vnet_cidr   = "10.10.0.0/16"
  spoke_vnet_cidr = "10.20.0.0/16"
}

############################################
# 9. POLICY + RBAC
############################################
module "policy" {
  source = "Azure/avm-res-authorization-policyassignment/azurerm"

  policy_definition_id = var.policy_definition_id
  scope                = var.subscription_id
}

############################################
# 10. CI/CD AGENTS
############################################
module "agents" {
  source = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"

  name                = "${var.prefix}-agents"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  instances           = 2
}

############################################
# 11. MONITORING
############################################
module "monitor" {
  source = "Azure/avm-res-insights-diagnosticsetting/azurerm"

  target_resource_id = module.vm.id
}

############################################
# 12. FUNCTION + PRIVATE ENDPOINT
############################################
module "function" {
  source = "Azure/avm-res-web-functionapp/azurerm"

  name                = "${var.prefix}-func"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_endpoint" "func_pe" {
  name                = "${var.prefix}-func-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.vnet.subnets["app"].id
}

############################################
# 13. LANDING ZONE
############################################
module "landingzone" {
  source = "Azure/avm-ptn-landingzone/azurerm"

  environment = var.environment
}

############################################
# 14. AVD
############################################
module "avd" {
  source = "Azure/avm-res-desktopvirtualization-hostpool/azurerm"

  name                = "${var.prefix}-avd"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

############################################
# 15. PRIVATE DNS
############################################
module "privatedns" {
  source = "Azure/avm-res-network-privatednszone/azurerm"

  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}