#!/bin/bash
set -e

# Update & install dependencies
apt update
DEBIAN_FRONTEND=noninteractive apt install -y nginx mariadb-server redis-server php8.1 php8.1-cli php8.1-fpm php8.1-mysql php8.1-gd php8.1-mbstring php8.1-zip php8.1-bcmath php8.1-curl php8.1-xml git unzip curl composer

# Unduh Panel Pterodactyl
cd /workspaces/$(basename "$PWD")
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
mkdir -p panel && tar -xzvf panel.tar.gz -C panel --strip-components=1
cd panel

# Permission
chmod -R 755 storage bootstrap/cache

# Setup Laravel env & install
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# Setup database
service mysql start
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'ptero'@'localhost' IDENTIFIED BY 'ptero123';
GRANT ALL ON panel.* TO 'ptero'@'localhost';
FLUSH PRIVILEGES;
EOF

# Config DB
sed -i "s/DB_DATABASE=panel/DB_DATABASE=panel/" .env
sed -i "s/DB_USERNAME=pterodactyl/DB_USERNAME=ptero/" .env
sed -i "s/DB_PASSWORD=/DB_PASSWORD=ptero123/" .env

php artisan migrate --seed --force

# Buat admin
php artisan p:user:make --email=admin@local.host --password=pteroadmin --admin

# Nginx setup
cat > /etc/nginx/sites-available/pterodactyl <<EOL
server {
    listen 8080;
    server_name _;

    root $(pwd)/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOL

ln -sf /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
nginx -t

# Start services
service php8.1-fpm start
service redis-server start
service mysql restart
service nginx restart

echo "✅ Panel siap di http://localhost:8080"
echo "   Login dengan email admin@local.host, password pteroadmin"
