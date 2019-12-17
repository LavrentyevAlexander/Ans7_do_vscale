terraform {
	required_version =  ">= 0.11.0"
	}

variable "do_token" {}
variable "rebrain_key_name" {}
variable "lavrentyev_key_name" {}
variable "dr_name" {type = "list"}
variable "vscale_token" {}
variable "aws_my_access_key" {}
variable "aws_my_secret_key" {}
variable "devs" {type = "list"}
variable "os" {type = "map"}

provider "aws" {
        region = "eu-west-1"
        access_key = "${var.aws_my_access_key}"
        secret_key = "${var.aws_my_secret_key}"
}

provider "vscale" {
        token = "${var.vscale_token}"
}

provider "digitalocean" {
        token = "${var.do_token}"
}

data "aws_route53_zone" "rebrain" {
        name = "devops.rebrain.srwx.net."
}


resource "digitalocean_tag" "AlexanderLavrentyev_lavrentyevas" {
                name = "AlexanderLavrentyev_lavrentyevas"
        }

data "digitalocean_ssh_key" "REBRAIN" {
                name = "${var.rebrain_key_name}"
        }

data "digitalocean_ssh_key" "LAVRENTYEV" {
                name = "${var.lavrentyev_key_name}"
        }

resource "vscale_ssh_key" "las_ans" {
  name = "lavrentyev_key"
  key  = "${file("/home/las/.ssh/id_rsa.pub")}"
}

resource "random_password" "root_password" {
	count = "${length(var.devs)}"
	length = 16
  	special = true
  	override_special = "_%@"
	upper = true
	lower = true
	number = true
}

resource "vscale_scalet" "LavrentyevAS" {
  count = "${length(var.devs)}" 
  ssh_keys  = ["${vscale_ssh_key.las_ans.id}"]
  make_from = "${var.os["${element(var.devs, count.index)}"]}"
  location  = "msk0"
  rplan     = "medium"
  name      = "${element(var.devs, count.index)}.devops.rebrain.srwx.net"

	provisioner "remote-exec" {
		inline = ["echo root:${element(random_password.root_password.*.result, count.index)} | chpasswd", 
	]
		connection {
			host = "${self.public_address}"
			type = "ssh"
			user = "root"
			private_key = "${file("/home/las/.ssh/id_rsa")}"
			}
		}
	provisioner "local-exec" {
	        command = "echo ${self.name} ${self.public_address} ${element(random_password.root_password.*.result, count.index)} >> devs.txt"
			}
}

resource "aws_route53_record" "las_ans" {
	count = "${length(var.devs)}"
        zone_id = "${data.aws_route53_zone.rebrain.zone_id}"
        name = "${element(var.devs, count.index)}.devops.rebrain.srwx.net"
        type = "A"
        ttl = "300"
        records = ["${element(vscale_scalet.LavrentyevAS.*.public_address, count.index)}"]
}

data "template_file" "dev_ansible" {
  count = "${length(var.devs)}"
  template = "${file("templates/hostname.tpl")}"
  vars = {
    name  = "${element(var.devs, count.index)}"
  }
}

data "template_file" "ansible_inventory" {
  template = "${file("templates/ansible_inventory.tpl")}"
  vars = {
    web_hosts   = "${join("\n",data.template_file.dev_ansible.*.rendered)}"
  }
}

	resource "null_resource" "local" {
  		triggers = {
    		template = "${data.template_file.ansible_inventory.rendered}"
  	}

  	provisioner "local-exec" {
    		command = "echo \"${data.template_file.ansible_inventory.rendered}\" > inventory/prod.yml"
 		 }
	}

resource "digitalocean_droplet" "ops2" {
  count = "${length(var.dr_name)}"
  image  = "centos-7-x64"
  name   = "${element(var.dr_name, count.index)}"
  region = "nyc1"
  size   = "s-1vcpu-1gb"
  ssh_keys = ["${data.digitalocean_ssh_key.REBRAIN.fingerprint}","${data.digitalocean_ssh_key.LAVRENTYEV.fingerprint}"]
  tags = ["${digitalocean_tag.AlexanderLavrentyev_lavrentyevas.id}"]
		
        provisioner "remote-exec" {
                inline = ["echo root:12345678 | chpasswd",
        ]
                connection {
                        host = "${self.ipv4_address}"
                        type = "ssh"
                        user = "root"
                        private_key = "${file("/home/las/.ssh/id_rsa")}"
                        }
                }
        provisioner "local-exec" {
                command = "echo ${self.name} ${self.ipv4_address} 12345678 >> devs.txt"
                        }

}

resource "aws_route53_record" "las_DO" {
        count = "${length(var.dr_name)}"
        zone_id = "${data.aws_route53_zone.rebrain.zone_id}"
        name = "${element(var.dr_name, count.index)}.devops.rebrain.srwx.net"
        type = "A"
        ttl = "300"
        records = ["${element(digitalocean_droplet.ops2.*.ipv4_address, count.index)}"]
}

