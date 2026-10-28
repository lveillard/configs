terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# One workspace per box: terraform workspace select <box name>. Settings come from ../boxes.json.
locals {
  catalogue = jsondecode(file("${path.module}/../boxes.json"))
  box       = one([for b in local.catalogue.boxes : b if b.name == terraform.workspace])
  tf        = local.box.terraform
  name      = local.box.name
  tags = {
    company      = local.box.label
    purpose      = "development"
    owner        = local.catalogue.user
    architecture = "amd64"
    managed_by   = "terraform"
  }
}

provider "azurerm" {
  subscription_id = local.box.subscriptionId
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name}"
  location = local.catalogue.region
  tags     = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [local.tf.addressSpace]
  tags                = local.tags
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [cidrsubnet(local.tf.addressSpace, 8, 0)]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  # Daily access goes over Tailscale; public SSH opens only while bootstrapping a new box.
  dynamic "security_rule" {
    for_each = var.ssh_source_ip == "" ? [] : [var.ssh_source_ip]
    content {
      name                       = "SSH-bootstrap"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "${security_rule.value}/32"
      destination_address_prefix = "*"
    }
  }

  # Lets Tailscale peers connect directly instead of through DERP relays.
  security_rule {
    name                       = "Tailscale-direct"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "41641"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "ip" {
  name                = "${local.name}-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [local.catalogue.zone]
  tags                = local.tags
}

resource "azurerm_network_interface" "nic" {
  name                = "${local.name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = local.name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = local.tf.vmSize
  zone                  = local.catalogue.zone
  admin_username        = local.catalogue.user
  network_interface_ids = [azurerm_network_interface.nic.id]
  tags                  = local.tags

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  admin_ssh_key {
    username   = local.catalogue.user
    public_key = file(pathexpand("~/.ssh/${local.name}_ed25519.pub"))
  }

  os_disk {
    name                 = "${local.name}-os-amd64-${local.tf.osDiskGb}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = local.tf.osDiskGb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", { name = local.name, prompt_label = local.box.label, user = local.catalogue.user }))

  lifecycle {
    ignore_changes = [custom_data, source_image_reference[0].version]
  }
}
