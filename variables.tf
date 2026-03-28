variable "prefix" {}
variable "location" { default = "uksouth" }
variable "rg_name" {}

variable "admin_username" {}
variable "sql_admin" {}
variable "sql_password" {
  sensitive = true
}

variable "subscription_id" {}
variable "policy_definition_id" {}

variable "environment" {
  default = "dev"
}