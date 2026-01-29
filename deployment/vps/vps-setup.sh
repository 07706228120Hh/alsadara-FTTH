#!/bin/bash
# ========================================
# Sadara Platform - VPS Setup Script
# VPS: 72.61.183.61 (Hostinger Ubuntu 24.04)
# ========================================

echo "🚀 Starting Sadara Platform VPS Setup..."

# ============ 1. Update System ============
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ============ 2. Install PostgreSQL 16 ============
echo "🐘 Installing PostgreSQL 16..."
sudo apt install -y postgresql postgresql-contrib

# Start PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# ============ 3. Configure PostgreSQL ============
echo "⚙️ Configuring PostgreSQL..."

# Create database and user
sudo -u postgres psql << EOF
-- Create user
CREATE USER sadara_user WITH PASSWORD 'sadara_secure_password_2024';

-- Create database
CREATE DATABASE sadara_db OWNER sadara_user;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE sadara_db TO sadara_user;

-- Enable UUID extension
\c sadara_db
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\q
EOF

echo "✅ PostgreSQL configured successfully!"

# ============ 4. Install .NET 9 SDK ============
echo "🔷 Installing .NET 9 SDK..."
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

sudo apt update
sudo apt install -y dotnet-sdk-9.0

# Verify installation
dotnet --version

# ============ 5. Install Nginx ============
echo "🌐 Installing Nginx..."
sudo apt install -y nginx
sudo systemctl enable nginx

# ============ 6. Configure Firewall ============
echo "🔥 Configuring firewall..."
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 5000/tcp  # API (temporary for testing)
sudo ufw --force enable

# ============ 7. Create Application Directory ============
echo "📁 Creating application directory..."
sudo mkdir -p /var/www/sadara-api
sudo chown -R $USER:$USER /var/www/sadara-api

# ============ 8. Create Nginx Configuration ============
echo "📝 Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/sadara-api << 'NGINX'
server {
    listen 80;
    server_name 72.61.183.61;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

# Enable site
sudo ln -sf /etc/nginx/sites-available/sadara-api /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# ============ 9. Create Systemd Service ============
echo "⚡ Creating systemd service..."
sudo tee /etc/systemd/system/sadara-api.service << 'SERVICE'
[Unit]
Description=Sadara Platform API
After=network.target postgresql.service

[Service]
WorkingDirectory=/var/www/sadara-api
ExecStart=/usr/bin/dotnet Sadara.API.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=sadara-api
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload

echo "✅ VPS Setup completed!"
echo ""
echo "📋 Next Steps:"
echo "1. Publish the API: dotnet publish -c Release -o /var/www/sadara-api"
echo "2. Copy files to VPS"
echo "3. Start the service: sudo systemctl start sadara-api"
echo "4. Enable on boot: sudo systemctl enable sadara-api"
echo ""
echo "🔑 Database Connection String:"
echo "Host=localhost;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024"
