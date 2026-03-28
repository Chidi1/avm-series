output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "vnet_id" {
  value = module.vnet.id
}

output "aks_name" {
  value = module.aks.name
}

output "sql_server" {
  value = module.sql_server.name
}

output "app_url" {
  value = module.appservice.default_hostname
}

output "acr_login_server" {
  value = module.acr.login_server
}