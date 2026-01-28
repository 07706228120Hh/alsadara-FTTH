# 🚀 دليل النشر

## 📋 المتطلبات

### على الخادم (VPS)
- Ubuntu 24.04 LTS
- .NET 9 Runtime
- PostgreSQL 16
- Nginx
- Certbot (SSL)

### بيانات VPS
```
IP: 72.61.183.61
OS: Ubuntu 24.04 LTS
RAM: 8GB
CPU: 2 Cores
Disk: 100GB
```

---

## 🔧 خطوات الإعداد

### 1️⃣ تحديث النظام
```bash
sudo apt update && sudo apt upgrade -y
```

### 2️⃣ تثبيت .NET 9
```bash
wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 9.0

# إضافة للمسار
echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.bashrc
echo 'export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.bashrc
source ~/.bashrc
```

### 3️⃣ تثبيت PostgreSQL
```bash
sudo apt install postgresql postgresql-contrib -y
sudo systemctl start postgresql
sudo systemctl enable postgresql

# إنشاء قاعدة البيانات
sudo -u postgres psql
CREATE USER sadara WITH PASSWORD 'your_secure_password';
CREATE DATABASE sadara_db OWNER sadara;
\q
```

### 4️⃣ تثبيت Nginx
```bash
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

### 5️⃣ تكوين Nginx
```bash
sudo nano /etc/nginx/sites-available/sadara-api
```

```nginx
server {
    listen 80;
    server_name api.sadara.iq;

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
```

```bash
sudo ln -s /etc/nginx/sites-available/sadara-api /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 6️⃣ تثبيت SSL
```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d api.sadara.iq
```

---

## 📦 نشر API

### على جهاز التطوير
```powershell
cd C:\SadaraPlatform\src\Backend\API\Sadara.API
dotnet publish -c Release -o ./publish
```

### نقل للخادم
```powershell
scp -r ./publish/* root@72.61.183.61:/var/www/sadara-api/
```

### على الخادم
```bash
# إنشاء Service
sudo nano /etc/systemd/system/sadara-api.service
```

```ini
[Unit]
Description=Sadara Platform API
After=network.target

[Service]
WorkingDirectory=/var/www/sadara-api
ExecStart=/root/.dotnet/dotnet /var/www/sadara-api/Sadara.API.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=sadara-api
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://localhost:5000

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl start sadara-api
sudo systemctl enable sadara-api
sudo systemctl status sadara-api
```

---

## 🔍 التحقق

```bash
# فحص حالة API
curl http://localhost:5000/health

# فحص من الخارج
curl https://api.sadara.iq/health
```

---

## 📝 الصيانة

### عرض السجلات
```bash
sudo journalctl -u sadara-api -f
```

### إعادة التشغيل
```bash
sudo systemctl restart sadara-api
```

### تحديث API
```bash
sudo systemctl stop sadara-api
# نقل الملفات الجديدة
sudo systemctl start sadara-api
```
