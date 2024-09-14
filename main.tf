provider "aws" {
  region = "us-east-1"  # Change this to your preferred region
}

# VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Public Subnet in us-east-1a
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

# Private Subnet in us-east-1b
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

# Route Table for Public Subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_route_table_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

# Route Table for Private Subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

resource "aws_route_table_association" "private_route_table_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Create CMK Key
resource "aws_kms_key" "cmk" {
  description             = "CMK for EC2 and RDS encryption"
  deletion_window_in_days = 10
}

# EC2 Instance in Private Subnet with EBS Encrypted using CMK
resource "aws_instance" "private_ec2" {
  ami = "ami-07cc1bbe145f35b58" # Choose the correct AMI for your region
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id

  ebs_block_device {
    device_name          = "/dev/sda1"
    volume_size          = 30
    encrypted            = true
    kms_key_id           = aws_kms_key.cmk.arn
  }

  associate_public_ip_address = false
}

# RDS Subnet Group with coverage in two AZs
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.public_subnet.id]  # Ensures at least two AZs
}

# RDS Instance in Private Subnet with encryption using CMK
resource "aws_db_instance" "rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "admin123"
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name

  storage_encrypted = true
  kms_key_id  = aws_kms_key.cmk.arn
  skip_final_snapshot = true
}
