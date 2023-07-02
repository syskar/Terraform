I had created a vm with the hostname as nginx, along with 2 labels named 
label key:value
name: nginx1
env: dev

////

Place the public key in the metadata on the console, by which the key will be used along with private key to execute the command on the remote server. Make sure the ssh-key is created with the user name as ansible

gcp console --> compute engine --> Metadata --> ssh keys --> paste the key


create a user ansible and their ssh-keys. Use the user name as ansible along with the private key while running the command. 

ssh-keygen -t rsa -c ansible

//////

gcp-inv.yaml file created as mentioned below

---
plugin: gcp_compute
projects:
  - testproject-390101
auth_kind: serviceaccount
service_account_file: /home/testsyskar/testproject-terraformtest-key.json
hostnames:
  - name
keyed_groups:
  - key: labels
    prefix: label
  - key: zone
groups:
  #development: "'env' in (labels|list)"
  web: "'nginx' in name"

//////  

filters:
  - machineType = n1-standard-1
  - scheduling.automaticRestart = true AND machineType = n1-standard-1

///



ansible-inventory -i gcp.yaml  --list

Bottom of the output will loks like 

    "all": {
        "children": [
            "ungrouped",
            "web",
            "label_name_nginx1",
            "label_env_dev"
        ]
    },
    "label_env_dev": {
        "hosts": [
            "nginx"
        ]
    },
    "label_name_nginx1": {
        "hosts": [
            "nginx"
        ]
    },
    "web": {
        "hosts": [
            "nginx"
        ]
    }

////

--list will give the complete information of the instance

/// 

In the above we can able to see the hostname as nginx, if we need to have ip instaed of hostnames , then we can comment the hostnames parameter in the above code 

///

run the command as 

ansible-inventory -i gcp.yaml  --graph

and the output like 

@all:
  |--@ungrouped:
  |--@web:
  |  |--34.66.205.88
  |--@label_name_nginx1:
  |  |--34.66.205.88
  |--@label_env_dev:
  |  |--34.66.205.88
  
////

Group header "web" is the group generated using dynamic inventory with the help of hostname. if the hostname starts as web-, then we need to mention the filter in the ansible plugin as 

groups:
  web: "'web-' in name"
  

///

Group headers label_name_nginx1 and label_env_dev are the groups created based on criteria label


  |--@label_name_nginx1:
  |  |--34.66.205.88
  |--@label_env_dev:
  |  |--34.66.205.88
  
  
////

use the group name without '@' to apply the playbook for a specific group of servers. below is the ansible adhoc command to check the ping status. 




ansible web -i gcp.yaml -m ping --private-key /.ssh/id_rsa  -u ansible




////////


Using Dynamic Groups
You can create dynamic groups using host variables with the constructed keyed_groups option. The option groups can also be used to create groups and create and modify host variables. Syntax for keyed groups and groups that use tags follows:

keyed_groups
- key: freeform_tags.<tag key>
  prefix: <my_prefix>
- key: defined_tags.<namespace>.<tag key>
  prefix: <my_prefix>
groups:
  <group_name>: "'<tag_value>' == freeform_tags.<tag_key>"
  <group_name>: "'<tag_value>' == defined_tags.<namespace>.<tag_key>"
  <group_name>: "'<tag_key>' in defined_tags.<namespace>"

/////

installing nginx on the remote server using the dynamic inventory 

ansible-playbook nginx.yaml  -i ./inventory/gcp.yaml -l label_env_dev --private-key ./.ssh/id_rsa  -u ansible

//

verifying it using adhoc command 

ansible web -i ./inventory/gcp.yaml -m get_url -a 'url=http://localhost dest=/tmp mode=0755' --private-key ./.ssh/id_rsa  -u ansible

