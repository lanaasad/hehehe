#!/bin/bash

NGINX_CONF="/etc/nginx/conf.d"

get_vps_info() {
    clear
    IP=$(curl -s ifconfig.me)
    REGION=$(curl -s ipinfo.io/region)
    COUNTRY=$(curl -s ipinfo.io/country)
    UPTIME=$(uptime -p)
    echo "=== Informasi VPS ==="
    echo "IP Public : $IP"
    echo "Region    : $REGION"
    echo "Country   : $COUNTRY"
    echo "Uptime    : $UPTIME"
    echo "====================="
}

add_domain() {
    read -p "Masukkan nama domain: " DOMAIN
    read -p "Masukkan port project: " PORT
    read -p "Aktifkan SSL dengan Certbot? (y/n): " SSL

    if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
        echo "Domain dan port wajib diisi"
        return
    fi

    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "Port harus berupa angka"
        return
    fi

    CONF_FILE="$NGINX_CONF/$DOMAIN.conf"

    if [ -f "$CONF_FILE" ]; then
        echo "Konfigurasi untuk $DOMAIN sudah ada."
        read -p "Hapus konfigurasi lama dan buat ulang? (y/n): " REPLACE
        if [[ "$REPLACE" == "y" || "$REPLACE" == "Y" ]]; then
            rm -f "$CONF_FILE"
        else
            return
        fi
    fi

    if [[ "$SSL" == "y" || "$SSL" == "Y" ]]; then
        if ! command -v certbot &> /dev/null; then
            echo "Installing Certbot..."
            apt update
            apt install certbot python3-certbot-nginx -y
        fi
        
        # Create initial HTTP configuration for certbot
        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://172.17.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        
        nginx -t && systemctl restart nginx
        
        echo "Mengaktifkan SSL untuk $DOMAIN..."
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
        
        # After certbot, update the configuration to match the desired format
        cat > "$CONF_FILE" <<EOF
server {
    server_name $DOMAIN;
    location / {
        proxy_pass http://172.17.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    } # managed by Certbot
    listen 80;
    server_name $DOMAIN;
    return 404; # managed by Certbot
}
EOF
        
        nginx -t && systemctl restart nginx
        echo "SSL berhasil diaktifkan untuk $DOMAIN"
    else
        # If no SSL, create simple HTTP configuration
        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        proxy_pass http://172.17.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_Set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        
        nginx -t
        if [ $? -ne 0 ]; then
            echo "Konfigurasi Nginx error. Periksa file $CONF_FILE"
            return
        fi

        systemctl restart nginx
        if [ $? -ne 0 ]; then
            echo "Gagal restart Nginx"
            return
        fi

        echo "Domain $DOMAIN berhasil ditambahkan di port $PORT"
    fi
}

list_domains() {
    echo "=== Daftar Domain ==="
    if [ -n "$(ls -A $NGINX_CONF 2>/dev/null)" ]; then
        ls $NGINX_CONF | sed 's/\.conf$//'
    else
        echo "Tidak ada domain"
    fi
}

manage_domain() {
    list_domains
    read -p "Masukkan nama domain untuk dikelola: " DOMAIN
    CONF_FILE="$NGINX_CONF/$DOMAIN.conf"
    if [ ! -f "$CONF_FILE" ]; then
        echo "Domain tidak ditemukan"
        return
    fi
    echo "1. Lihat konfigurasi"
    echo "2. Edit konfigurasi"
    echo "3. Perbarui SSL"
    read -p "Pilih opsi: " OPTION
    case $OPTION in
        1) 
            echo "=== Konfigurasi $DOMAIN ==="
            cat "$CONF_FILE"
            ;;
        2) 
            nano "$CONF_FILE"
            echo "Testing konfigurasi..."
            if nginx -t; then
                systemctl restart nginx
                echo "Konfigurasi berhasil diperbarui"
            else
                echo "Error dalam konfigurasi. Periksa kembali."
            fi
            ;;
        3)
            if command -v certbot &> /dev/null; then
                certbot --nginx -d "$DOMAIN"
                nginx -t && systemctl restart nginx
            else
                echo "Certbot tidak terinstall"
            fi
            ;;
        *)
            echo "Pilihan tidak valid"
            ;;
    esac
}

delete_domain() {
    list_domains
    read -p "Masukkan nama domain yang akan dihapus: " DOMAIN
    CONF_FILE="$NGINX_CONF/$DOMAIN.conf"
    if [ -f "$CONF_FILE" ]; then
        echo "Menghapus konfigurasi domain $DOMAIN..."
        
        # Remove SSL certificates if exists
        if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
            read -p "Hapus juga SSL certificate? (y/n): " DELETE_SSL
            if [[ "$DELETE_SSL" == "y" || "$DELETE_SSL" == "Y" ]]; then
                certbot delete --cert-name "$DOMAIN" 2>/dev/null
            fi
        fi
        
        rm -f "$CONF_FILE"
        if nginx -t && systemctl restart nginx; then
            echo "Domain $DOMAIN berhasil dihapus"
        else
            echo "Error saat restart nginx"
        fi
    else
        echo "Domain tidak ditemukan"
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Harap jalankan script ini dengan sudo"
    exit 1
fi

# Main menu loop
while true; do
    get_vps_info
    echo ""
    echo "=== Nginx Domain Manager ==="
    echo "1. Tambah domain"
    echo "2. List domain"
    echo "3. Kelola domain"
    echo "4. Hapus domain"
    echo "5. Keluar"
    echo "=========================="
    read -p "Pilih opsi: " MENU
    
    case $MENU in
        1) add_domain ;;
        2) list_domains ;;
        3) manage_domain ;;
        4) delete_domain ;;
        5) 
            echo "Terima kasih!"
            exit 0 
            ;;
        *) 
            echo "Pilihan tidak valid" 
            ;;
    esac
    
    echo ""
    read -p "Tekan enter untuk kembali ke menu..."
done
