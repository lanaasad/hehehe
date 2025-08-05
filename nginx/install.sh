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

    cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://$IP:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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

    if [[ "$SSL" == "y" || "$SSL" == "Y" ]]; then
        if ! command -v certbot &> /dev/null; then
            apt update
            apt install certbot python3-certbot-nginx -y
        fi
        certbot --nginx -d "$DOMAIN"
    fi
}

list_domains() {
    echo "=== Daftar Domain ==="
    ls $NGINX_CONF | sed 's/\.conf$//' || echo "Tidak ada domain"
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
    read -p "Pilih opsi: " OPTION
    if [ "$OPTION" == "1" ]; then
        cat "$CONF_FILE"
    elif [ "$OPTION" == "2" ]; then
        nano "$CONF_FILE"
        nginx -t && systemctl restart nginx
    fi
}

delete_domain() {
    list_domains
    read -p "Masukkan nama domain yang akan dihapus: " DOMAIN
    CONF_FILE="$NGINX_CONF/$DOMAIN.conf"
    if [ -f "$CONF_FILE" ]; then
        rm -f "$CONF_FILE"
        nginx -t && systemctl restart nginx
        echo "Domain $DOMAIN berhasil dihapus"
    else
        echo "Domain tidak ditemukan"
    fi
}

if [ "$EUID" -ne 0 ]; then
    echo "Harap jalankan script ini dengan sudo"
    exit 1
fi

while true; do
    get_vps_info
    echo "1. Tambah domain"
    echo "2. List domain"
    echo "3. Kelola domain"
    echo "4. Hapus domain"
    echo "5. Keluar"
    read -p "Pilih opsi: " MENU
    case $MENU in
        1) add_domain ;;
        2) list_domains ;;
        3) manage_domain ;;
        4) delete_domain ;;
        5) exit 0 ;;
        *) echo "Pilihan tidak valid" ;;
    esac
    read -p "Tekan enter untuk kembali ke menu"
done
