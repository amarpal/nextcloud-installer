#!/bin/bash
set -e

# nginx
sudo apt install -y nginx

# OpenSSL
sudo apt install -y openssl

# PostgreSQL
sudo apt install -y postgresql

# PHP
sudo apt install -y php-fpm

# Required prerequisites
sudo apt install -y php-common php-curl php-xml php-gd php-json php-mbstring php-zip

# Database connectors
#sudo apt install -y php-sqlite3
#sudo apt install -y php-mysql
sudo apt install -y php-pgsql

# Recommended packages
sudo apt install -y php-bz2 php-intl

# Required for specific apps
sudo apt install -y php-ldap php-smbclient php-imap php-ftp

# Recommended for specific apps (optional):
sudo apt install -y php-gmp

# Enhanced server performance
# sudo apt install -y php-apcu
# sudo apt install -y php-memcached
sudo apt install -y php-redis

# Preview generation
sudo apt install -y php-imagick
sudo apt install -y ffmpeg
sudo apt install -y libreoffice

# Redis
sudo apt install -y redis-server

# Let's Encrypt
sudo apt install certbot
sudo apt install python-certbot-nginx
