output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.vm.name
}

output "nsg_name" {
  value = azurerm_network_security_group.nsg.name
}

output "public_ip" {
  value = azurerm_public_ip.ip.ip_address
}
