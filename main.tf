provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "my_network" {
  name = "my-network"
}

resource "yandex_vpc_subnet" "my_subnet" {
  name           = "my-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.my_network.id
  v4_cidr_blocks = ["192.168.0.0/24"]
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "ssh_private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "~/.ssh/jmix"
}

resource "local_file" "ssh_public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "~/.ssh/jmix.pub"
}

resource "yandex_compute_instance" "vm" {
  name       = "jmix-bookstore-vm"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = "fd8br3t8b42gt7cheq7a" # Ubuntu 24.04 LTS
      size     = 20
      type     = "network-ssd"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.my_subnet.id
    nat       = true
  }
  metadata = {
    ssh-keys = "yc-user:${tls_private_key.ssh_key.public_key_openssh}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo docker run -d --name jmix-app -p 80:8080 jmix/jmix-bookstore"
    ]
    connection {
      type        = "ssh"
      user        = "yc-user"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.network_interface[0].nat_ip_address
    }
  }
}

output "ssh_command" {
  value = "ssh -i ${local_file.ssh_private_key.filename} yc-user@${yandex_compute_instance.vm.network_interface.0.nat_ip_address}"
}

output "app_url" {
  value = "http://${yandex_compute_instance.vm.network_interface.0.nat_ip_address}:80"
}
