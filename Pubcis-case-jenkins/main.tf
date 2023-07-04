locals {
  project_id = "testproject-390101"
  region = "us-central1" 
  zone="us-central1-c"
  image="debian-11-bullseye-v20230615"
  ssh_user = "ansible"
  private_key_path = "/home/testsyskar/.ssh/id_rsa"
  service-acc = "terraformtest@testproject-390101.iam.gserviceaccount.com"
  account_scopes=["https://www.googleapis.com/auth/cloud-platform"]
}

provider "google" {
  project=local.project_id
  region = local.region
  //credentials = "${file("F:/Guides/Terraform/Udemy/practice/GCP/testproject-terraformtest-key.json")}"
  //credentials = "${file("/home/testsyskar/testproject-terraformtest-key.json")}"
  scopes = local.account_scopes
}
provider "google-beta" {
  project=local.project_id
  region = local.region
  //credentials = "${file("F:/Guides/Terraform/Udemy/practice/GCP/testproject-terraformtest-key.json")}"
  //credentials = "${file("/home/testsyskar/testproject-terraformtest-key.json")}"
  scopes = local.account_scopes
}

resource "google_compute_network" "vpc_network" {
name = "pub-vpc"
auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public-subnetwork" {
provider = google-beta
purpose = "PRIVATE"
name = "pub-vpc-subnet-us-central1"
ip_cidr_range = "10.0.1.0/24"
region = local.region
network = google_compute_network.vpc_network.name
}

# create a public ip for nat service
resource "google_compute_address" "nat-ip" {
  name = "web-nap-ip"
  project = local.project_id
  region  = local.region
}

resource "google_compute_router" "router" {
  name    = "pub-router"
  region  = google_compute_subnetwork.public-subnetwork.region
  network = google_compute_network.vpc_network.name

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "pub-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  nat_ips = [ google_compute_address.nat-ip.self_link ]
  depends_on = [ google_compute_address.nat-ip ]
}

resource "google_compute_firewall" "allow-web-access" {
  name    = "allow-web-access"
  project = local.project_id
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["80","8080"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["http"]
}


resource "google_compute_firewall" "allow-ssh" {
  name    = "allow-ssh"
  project = local.project_id
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["ssh"]
}

resource "google_compute_firewall" "allow-rdp" {
  name    = "allow-rdp"
  project = local.project_id
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["rdp"]
}

resource "google_compute_firewall" "allow-internal" {
  name    = "allow-internal"
  project = local.project_id
  network = google_compute_network.vpc_network.id
  allow {
  protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["ssh","rdp","http"]
}


# allow access from health check ranges
resource "google_compute_firewall" "healthcheck-access" {
  name          = "web-mig-hc-fw"
  direction     = "INGRESS"
  network       = google_compute_network.vpc_network.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
    ports = ["80","8080"]
  }
  target_tags = ["http"]
}

# instance template
resource "google_compute_instance_template" "web_inst_temp" {
  name         = "web-instance-template"
  machine_type = "e2-small"
  tags = ["ssh","http"]

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.public-subnetwork.id
    /*access_config {
      # add external ip to fetch packages
    }*/
  }
  disk {
    source_image = local.image
    auto_delete  = true
    boot         = true
  }
  metadata_startup_script = "sudo apt-get update;sudo apt-get install -y apache2;sudo service apache2 restart;sudo sed -i 's/80/8080/g' /etc/apache2/ports.conf;sudo sed -i 's/80/8080/g' /etc/apache2/sites-enabled/000-default.conf;sudo service apache2 restart"

  lifecycle {
    create_before_destroy = true
  }
}

# load balancer setup 

# determine whether instances are responsive and able to do work
resource "google_compute_health_check" "healthcheck" {
  name = "web-healthcheck"
  timeout_sec = 10
  check_interval_sec = 10
  
  http_health_check {
    port = 8080
    port_specification = "USE_FIXED_PORT"
    proxy_header       = "NONE"
    request_path       = "/"
  }
}

# defines a group of virtual machines that will serve traffic for load balancing
resource "google_compute_backend_service" "backend_service" {
  name = "web-backend-service"
  project = local.project_id
  port_name = "http-fwd"
  protocol = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks = [google_compute_health_check.healthcheck.id]
  backend {
    group = "${google_compute_instance_group_manager.web_mig_group.instance_group}"
    balancing_mode = "RATE"
    max_rate_per_instance = 100
  }
}

# used to route requests to a backend service based on rules that you define for the host and path of an incoming URL
resource "google_compute_url_map" "url_map" {
  name = "web-load-balancer"
  project = local.project_id
  default_service = google_compute_backend_service.backend_service.id
}

# used by one or more global forwarding rule to route incoming HTTP requests to a URL map
resource "google_compute_target_http_proxy" "target_http_proxy" {
  name = "web-proxy"
  project = local.project_id
  url_map = google_compute_url_map.url_map.id
}


# used to forward traffic to the correct load balancer for HTTP load balancing
resource "google_compute_global_forwarding_rule" "global_forwarding_rule" {
  name = "web-global-forwarding-rule"
  project = local.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target = google_compute_target_http_proxy.target_http_proxy.id
  port_range = "80-80"
}


# creates a group of virtual machine instances
resource "google_compute_instance_group_manager" "web_mig_group"{
  name = "web-vm-group"
  project = local.project_id
  base_instance_name = "web"
  zone = local.zone
  version {
    instance_template  = google_compute_instance_template.web_inst_temp.self_link
    }
  named_port {
    name = "http-fwd"
    port = 8080 # earlier it is 80
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.healthcheck.id
    initial_delay_sec = 300
  }
}

# automatically scale virtual machine instances in managed instance groups according to an autoscaling policy
resource "google_compute_autoscaler" "autoscaler" {
  name = "web-autoscaler"
  project = local.project_id
  zone = local.zone
  target  = "${google_compute_instance_group_manager.web_mig_group.self_link}"
  autoscaling_policy {
    min_replicas = "2"
    max_replicas = "4"
    cooldown_period = "120"
    
    cpu_utilization {
      target = 0.8
    }
  }
}
# show external ip address of load balancer
output "load-balancer-ip-address" {
  value = google_compute_global_forwarding_rule.global_forwarding_rule.ip_address
}