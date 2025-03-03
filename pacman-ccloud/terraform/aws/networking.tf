###########################################
################### VPC ###################
###########################################

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = var.global_prefix
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = var.global_prefix
  }
}

resource "aws_eip" "default" {
  depends_on = [aws_internet_gateway.default]
  vpc = true
  tags = {
    Name = var.global_prefix
  }
}

resource "aws_nat_gateway" "default" {
  depends_on = [aws_internet_gateway.default]
  allocation_id = aws_eip.default.id
  subnet_id = aws_subnet.public_subnet_1.id
  tags = {
    Name = var.global_prefix
  }
}

resource "aws_route" "default" {
  route_table_id = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.default.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "${var.global_prefix}-private-route-table"
  }
}

resource "aws_route" "private_route_2_internet" {
  route_table_id = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.default.id
}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id = aws_subnet.public_subnet_1.id
  route_table_id = aws_vpc.default.main_route_table_id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id = aws_subnet.public_subnet_2.id
  route_table_id = aws_vpc.default.main_route_table_id
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(data.aws_availability_zones.available.names)
  subnet_id = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

###########################################
################# Subnets #################
###########################################

variable "reserved_cidr_blocks" {
  type = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
    "10.0.4.0/24",
    "10.0.5.0/24",
    "10.0.6.0/24",
  ]
}

resource "aws_subnet" "private_subnet" {
  count = length(data.aws_availability_zones.available.names)
  vpc_id = aws_vpc.default.id
  cidr_block = element(var.reserved_cidr_blocks, count.index)
  map_public_ip_on_launch = false
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.global_prefix}-private-subnet-${count.index}"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.7.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.global_prefix}-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.8.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name = "${var.global_prefix}-public-subnet-2"
  }
}

resource "aws_subnet" "bastion_server" {
  count = var.instance_count["bastion_server"] >= 1 ? 1 : 0
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.9.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${var.global_prefix}-bastion-server"
  }
}

###########################################
############# Security Groups #############
###########################################

resource "aws_security_group" "load_balancer" {
  name = "${var.global_prefix}-load-balancer"
  description = "Load Balancer"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-load-balancer"
  }
}

resource "aws_security_group" "rest_proxy" {
  count = var.instance_count["rest_proxy"] >= 1 ? 1 : 0
  name = "${var.global_prefix}-rest-proxy"
  description = "REST Proxy"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.0.9.0/24"]
  }
  ingress {
    from_port = 8082
    to_port = 8082
    protocol = "tcp"
    cidr_blocks = [
      "10.0.1.0/24",
      "10.0.2.0/24",
      "10.0.3.0/24",
      "10.0.4.0/24",
      "10.0.5.0/24",
      "10.0.6.0/24",
      "10.0.7.0/24",
      "10.0.8.0/24",
    ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-rest-proxy"
  }
}

resource "aws_security_group" "ksql_server" {
  count = var.instance_count["ksql_server"] >= 1 ? 1 : 0
  name = "${var.global_prefix}-ksql-server"
  description = "KSQL Server"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.0.9.0/24"]
  }
  ingress {
    from_port = 8088
    to_port = 8088
    protocol = "tcp"

    cidr_blocks = [
      "10.0.1.0/24",
      "10.0.2.0/24",
      "10.0.3.0/24",
      "10.0.4.0/24",
      "10.0.5.0/24",
      "10.0.6.0/24",
      "10.0.7.0/24",
      "10.0.8.0/24",
    ]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-ksql-server"
  }
}

resource "aws_security_group" "bastion_server" {
  count = var.instance_count["bastion_server"] >= 1 ? 1 : 0
  name = "${var.global_prefix}-bastion-server"
  description = "Bastion Server"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.global_prefix}-bastion-server"
  }
}
