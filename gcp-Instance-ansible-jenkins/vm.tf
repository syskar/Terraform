# file/ansible_user is the ssh private key copied from the jenkins credential file using jenkins credentials

variable "ssh_private_key_file" {
  default = "/var/lib/jenkins/workspace/TF-ANS-VM-APACHE/files/ansible_user"
}

locals {
  project_id = "testproject-390101"
  region = "us-central" 
  zone="us-central1-c"
  image="debian-11-bullseye-v20230615"
  ssh_user = "ansible"
  //private_key_path = "F:/Guides/Terraform/Udemy/practice/GCP/testproject-terraformtest-key.json"
  //private_key_path = "/home/testsyskar/.ssh/id_rsa" #useful while running directly from the cloudshell or from a system
  ssh_private_key_content= file(var.ssh_private_key_file) #reading the file content from the above variable
  network = "testp-vpc"
  service-acc = "terraformtest@testproject-390101.iam.gserviceaccount.com"
}

provider "google" {
  project=local.project_id
  region = local.region
  //credentials = "${file("F:/Guides/Terraform/Udemy/practice/GCP/testproject-terraformtest-key.json")}"
  //credentials = "${file("/home/testsyskar/testproject-terraformtest-key.json")}"
}


resource "google_compute_firewall" "web" {
  name = "web-access"
  network = local.network

  allow {
    protocol = "tcp"
    ports = ["80"]
    }
  
  source_ranges = ["0.0.0.0/0"]
  //target_service_accounts = [local.service-acc]

}

resource "google_compute_instance" "nginxweb" {
  name = "nginx"
  machine_type = "e2-standard-2"
  zone=local.zone
  labels = {
    "env"  = "dev" 
    "name" = "nginx1" 
  }

  boot_disk {
    initialize_params {
      image=local.image
    }
  }

  network_interface {
    access_config {
      network_tier = "PREMIUM"
    }

    subnetwork = "projects/testproject-390101/regions/us-central1/subnetworks/testp-vpc-subnet1-us-central-1"
  }

  service_account {
    email = local.service-acc
    scopes = ["cloud-platform"]
  }

  provisioner "remote-exec" {
    inline = [ "echo 'wait till ssh is ready' " ]

    connection {
      type = "ssh"
      user = local.ssh_user
      //private_key = file(local.private_key_path)  
      private_key = local.ssh_private_key_content
      host = google_compute_instance.nginxweb.network_interface.0.access_config.0.nat_ip
    }  
  }

  /* provisioner "local-exec" {
    command = "ansible-playbook -i ${google_compute_instance.nginxweb.network_interface.0.access_config.0.nat_ip}, --private-key ${local.private_key_path} nginx.yaml"
  } */
}


