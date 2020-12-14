# Configure the AWS Provider
provider "aws" {
  region = "eu-central-1"
  access_key= "AKIA4H7GTLW5GK7UH5O7"
  secret_key= "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"
}

# # 1. Create vpc - Virtual Private Cloud 
resource "aws_vpc" "ibr" {
  cidr_block = "10.20.0.0/16"
}

# # 2. Create Internet Gateway//give acess from internt
resource "aws_internet_gateway" "gawa" {
    vpc_id = aws_vpc.ibr.id
}

# # 3. Create Custom Route Table
resource "aws_route_table" "ibr-route-table" {
  vpc_id = aws_vpc.ibr.id

  route {
    cidr_block = "0.0.0.0/0" # IPv4
    gateway_id = aws_internet_gateway.gawa.id
  }

  route {
    ipv6_cidr_block = "::/0" #IPv6
    gateway_id      = aws_internet_gateway.gawa.id
  }

  tags = {
    Name = "ibr"
  }
}

# # 4. Create a Subnet 
resource "aws_subnet" "ibr-subnet1" {
  vpc_id            = aws_vpc.ibr.id
  cidr_block        = "10.20.1.0/24" # Class C: 255.255.255.0 
  availability_zone = "eu-central-1a" # Availability Zone 
  tags = {
    Name = "ibr-subnet1"
  }
}

resource "aws_subnet" "ibr-subnet2" {
  vpc_id            = aws_vpc.ibr.id
  cidr_block        = "10.20.10.0/24" # Class C: 255.255.255.0 
  availability_zone = "eu-central-1b" # Availability Zone 
  tags = {
    Name = "ibr-subnet2"
  }
}

# # 5. Associate subnet with Route Table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.ibr-subnet1.id
  route_table_id = aws_route_table.ibr-route-table.id
}

resource "aws_route_table_association" "aa" {
  subnet_id      = aws_subnet.ibr-subnet2.id
  route_table_id = aws_route_table.ibr-route-table.id
}

# # 6. Create Security Group to allow port 22,80,443,5000
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.ibr.id

  ingress {
    description = "HTTPS"
    from_port   = 443  # 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "Docker"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# # 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.ibr-subnet1.id
  private_ips     = ["10.20.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}
resource "aws_network_interface" "web-server-nic1" {
  subnet_id       = aws_subnet.ibr-subnet2.id
  private_ips     = ["10.20.10.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# # 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.20.1.50"
  depends_on                = [aws_internet_gateway.gawa]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

resource "aws_eip" "one1" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic1.id
  associate_with_private_ip = "10.20.10.50"
  depends_on                = [aws_internet_gateway.gawa]
}

output "server_public_ip1" {
  value = aws_eip.one1.public_ip
}

# # 9. Create Ubuntu server and install/enable ubuntu
resource "aws_instance" "web-server-instance" {
  ami               =  "ami-0502e817a62226e03"
  instance_type     = "t2.micro"
  availability_zone = "eu-central-1a"
  key_name          = "ubu"



  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }
  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install docker.io -y
                sudo docker pull yousefkh97/flaskapp
                sudo docker run -p 5000:5000  yousefkh97/flaskapp
                EOF


  tags = {
    Name = "web-server"
  }
}


resource "aws_lb" "test" {
  name               = "lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web.id]
  subnets            = [aws_subnet.ibr-subnet1.id,aws_subnet.ibr-subnet2.id]

  enable_deletion_protection = true


  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "my-target-group" {
  name     = "lb-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.ibr.id
}

resource "aws_lb_target_group_attachment" "tg-attachment" {
  target_group_arn = aws_lb_target_group.my-target-group.arn
  target_id        = aws_instance.web-server-instance.id
  port             = 5000
}