resource "vkcs_networking_network" "app_network" {
  name           = "app-network-leskina"
  admin_state_up = true
}

resource "vkcs_networking_subnet" "app_subnet" {
  name       = "app-subnet-leskina"
  network_id = vkcs_networking_network.app_network.id
  cidr       = "192.168.100.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
  enable_dhcp = true
}

# Создаем отдельную сеть для БД
resource "vkcs_networking_network" "leskina_db_network" {
  name           = "db-network-leskina"
  admin_state_up = true
}

data "vkcs_images_image" "compute" {
  visibility = "public"
  default    = true
  properties = {
    mcs_os_distro  = "ubuntu"
    mcs_os_version = "22.04"
  }
}

resource "vkcs_networking_subnet" "leskina_db_subnet" {
  name       = "db-subnet-leskina"
  network_id = vkcs_networking_network.leskina_db_network.id
  cidr       = "192.168.200.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
  enable_dhcp = true
}

# Внешняя сеть
data "vkcs_networking_network" "extnet" {
  name = "ext-net"
}

# ОДИН роутер для обеих сетей
resource "vkcs_networking_router" "app_router" {
  name                = "app-router-leskina"
  admin_state_up      = true
  external_network_id = data.vkcs_networking_network.extnet.id
}

# Подключаем обе подсети к одному роутеру
resource "vkcs_networking_router_interface" "app_router_interface" {
  router_id = vkcs_networking_router.app_router.id
  subnet_id = vkcs_networking_subnet.app_subnet.id
}

resource "vkcs_networking_router_interface" "db_router_interface" {
  router_id = vkcs_networking_router.app_router.id
  subnet_id = vkcs_networking_subnet.leskina_db_subnet.id
}

# Группы безопасности
resource "vkcs_networking_secgroup" "haproxy_sg" {
  name = "haproxy-sg-leskina"
}

resource "vkcs_networking_secgroup" "app_sg" {
  name = "app-sg-leskina"
}

resource "vkcs_networking_secgroup" "db_sg" {
  name = "db-sg-leskina"
}

# Правила для HAProxy
resource "vkcs_networking_secgroup_rule" "haproxy_http" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.haproxy_sg.id
  port_range_min    = 80
  port_range_max    = 80
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "vkcs_networking_secgroup_rule" "haproxy_https" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.haproxy_sg.id
  port_range_min    = 443
  port_range_max    = 443
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "vkcs_networking_secgroup_rule" "haproxy_ssh" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.haproxy_sg.id
  port_range_min    = 22
  port_range_max    = 22
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
}

# Правила для app-серверов
resource "vkcs_networking_secgroup_rule" "app_ssh" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.app_sg.id
  port_range_min    = 22
  port_range_max    = 22
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "vkcs_networking_secgroup_rule" "app_from_haproxy" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.app_sg.id
  remote_group_id   = vkcs_networking_secgroup.haproxy_sg.id
  protocol          = "tcp"
  port_range_min    = 5000
  port_range_max    = 5000
}

# Правила для БД - ТОЛЬКО от app-серверов
resource "vkcs_networking_secgroup_rule" "db_mysql" {
  direction         = "ingress"
  security_group_id = vkcs_networking_secgroup.db_sg.id
  remote_group_id   = vkcs_networking_secgroup.app_sg.id
  protocol          = "tcp"
  port_range_min    = 3306
  port_range_max    = 3306
}

# ЗАРАНЕЕ СОЗДАЕМ FLOATING IP ДЛЯ ГАРАНТИРОВАННОГО ПОДКЛЮЧЕНИЯ
resource "vkcs_networking_floatingip" "haproxy_fip" {
  pool = data.vkcs_networking_network.extnet.name
}

resource "vkcs_networking_floatingip" "app1_fip" {
  pool = data.vkcs_networking_network.extnet.name
}

resource "vkcs_networking_floatingip" "app2_fip" {
  pool = data.vkcs_networking_network.extnet.name
}

# ВМ HAProxy
resource "vkcs_compute_instance" "haproxy" {
  name              = "haproxy-leskina"
  image_id          = data.vkcs_images_image.compute.id
  flavor_id         = "467c1b72-a6a2-4375-9cca-078cdc5bfdde"
  key_pair          = vkcs_compute_keypair.ssh_key.name
  security_group_ids   = [vkcs_networking_secgroup.haproxy_sg.name]

  block_device {
    uuid                  = data.vkcs_images_image.compute.id 
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 10
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = vkcs_networking_network.app_network.id
    fixed_ip_v4 = "192.168.100.10"
  }

  # ДОБАВЛЯЕМ USER_DATA ДЛЯ ГАРАНТИРОВАННОЙ НАСТРОЙКИ СЕТИ
  user_data = <<-EOF
    #cloud-config
    bootcmd:
      - [ sh, -c, "echo '=== Ensuring network configuration ===' > /tmp/cloud-init.log" ]
    runcmd:
      - [ sh, -c, "dhclient -v ens3 || true" ]
      - [ sh, -c, "systemctl restart systemd-networkd || true" ]
    EOF

  depends_on = [vkcs_networking_router_interface.app_router_interface]
}

# ВМ App серверы
resource "vkcs_compute_instance" "app_servers" {
  count             = 2
  name              = "app-server-${count.index + 1}-leskina"
  image_id          = data.vkcs_images_image.compute.id
  flavor_id         = "467c1b72-a6a2-4375-9cca-078cdc5bfdde"
  key_pair          = vkcs_compute_keypair.ssh_key.name
  security_group_ids   = [vkcs_networking_secgroup.app_sg.name]

  block_device {
    uuid                  = data.vkcs_images_image.compute.id 
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 10
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = vkcs_networking_network.app_network.id
    fixed_ip_v4 = "192.168.100.${20 + count.index}"
  }

  # USER_DATA ДЛЯ ГАРАНТИРОВАННОЙ НАСТРОЙКИ СЕТИ
  user_data = <<-EOF
    #cloud-config
    bootcmd:
      - [ sh, -c, "echo '=== Ensuring network configuration ===' > /tmp/cloud-init.log" ]
    runcmd:
      - [ sh, -c, "dhclient -v ens3 || true" ]
      - [ sh, -c, "systemctl restart systemd-networkd || true" ]
    EOF

  depends_on = [vkcs_networking_router_interface.app_router_interface]
}

# ПРИВЯЗЫВАЕМ FLOATING IP К ВМ
resource "vkcs_compute_floatingip_associate" "haproxy_fip_assoc" {
  floating_ip = vkcs_networking_floatingip.haproxy_fip.address
  instance_id = vkcs_compute_instance.haproxy.id
}

resource "vkcs_compute_floatingip_associate" "app1_fip_assoc" {
  floating_ip = vkcs_networking_floatingip.app1_fip.address
  instance_id = vkcs_compute_instance.app_servers[0].id
}

resource "vkcs_compute_floatingip_associate" "app2_fip_assoc" {
  floating_ip = vkcs_networking_floatingip.app2_fip.address
  instance_id = vkcs_compute_instance.app_servers[1].id
}

# MANAGED MYSQL DATABASE
data "vkcs_compute_flavor" "db" {
  name = "STD3-2-8" 
}

resource "vkcs_db_instance" "leskina_mysql_single" {
  name        = "leskina-mysql"
  flavor_id   = data.vkcs_compute_flavor.db.id
  size        = 20
  volume_type = "ceph-ssd"

  datastore {
    type    = "mysql"
    version = "8.0"
  }

  network {
    uuid = vkcs_networking_network.leskina_db_network.id
  }
  
  floating_ip_enabled = true
  availability_zone = "ME1"

  depends_on = [
    vkcs_networking_router_interface.db_router_interface
  ]
}

resource "time_sleep" "wait_for_mysql" {
  depends_on = [vkcs_db_instance.leskina_mysql_single]
  create_duration = "60s"
}

resource "vkcs_db_database" "leskina_test_db" {
  name    = "leskina_test_database"
  dbms_id = vkcs_db_instance.leskina_mysql_single.id

  depends_on = [time_sleep.wait_for_mysql]
}

# Создаем пользователя БД
resource "vkcs_db_user" "app_user" {
  name        = "appuser"
  password    = var.db_password
  dbms_id     = vkcs_db_instance.leskina_mysql_single.id
  
  depends_on = [time_sleep.wait_for_mysql]
}

# SSH ключ
resource "vkcs_compute_keypair" "ssh_key" {
  name       = "prod-key-leskina"
  public_key = ("****")
}

# Outputs
output "haproxy_public_ip" {
  value = vkcs_networking_floatingip.haproxy_fip.address
}

output "app1_public_ip" {
  value = vkcs_networking_floatingip.app1_fip.address
}

output "app2_public_ip" {
  value = vkcs_networking_floatingip.app2_fip.address
}

output "internal_ips" {
  value = {
    haproxy      = "192.168.100.10"
    app_server_1 = "192.168.100.20"
    app_server_2 = "192.168.100.21"
  }
}

output "mysql_endpoint" {
  value = vkcs_db_instance.leskina_mysql_single.ip[0]
}

output "database_config" {
  value = {
    host     = vkcs_db_instance.leskina_mysql_single.ip[0]
    name     = vkcs_db_database.leskina_test_db.name
    user     = vkcs_db_user.app_user.name
    password = var.db_password
    version  = "8.0"
    disk_size = "20GB"
    instance_class = "STD3-2-8"
  }
  sensitive = true
}