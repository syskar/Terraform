**Deploying Instance using MIG, configruing Apache and Load balancer"
------------------------------------------------------------------------------------
The following actions are performed using the code.

1. Creating VPC with one subnet on any region by chossing any CIDR range.
2. Creating and Cloud NAT and its route and applying it for the whole subnet.
3. Creating default firewall rules and the required load balancer firewall rules.
4. Creating Instance Template for deploying instance with debian OS.
5. Creating Managed Instance Group [MIG] with the above instance template along with auto scaling and health checks.
6. Creating Instance using the above MIG without public IP address.
7. Installing apache2 and changing the default listening port from 80 to 8080
8. Configuring External load balancer 
      a. Frontend with port 80
	  b. Backend pointed to the MIG created.
	  c. Configuring LB to redirect the traffic from 80 to 8080.

Pre-requisities.

Create a service account and generate the access key file as Json.

> Note: - Never upload the codes with the keys.