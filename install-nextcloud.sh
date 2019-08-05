#!/bin/bash
set -e

# Check arguments
if [ -z "$2" ]
then
    echo 'Usage:'
    echo './install-nextcloud.sh user@example.com cloud.example.com'
    exit 1
fi

# Define constants
EMAIL=$1
NCDOMAIN=$2
NCPATH='/var/www/nextcloud'
NCREPO='https://download.nextcloud.com/server/releases'
NCVERSION=$(curl -s -m 900 $NCREPO/ | sed --silent 's/.*href="nextcloud-\([^"]\+\).zip.asc".*/\1/p' | sort --version-sort | tail -1)
STABLEVERSION="nextcloud-$NCVERSION"
HTML='/var/www'
HTUSER='www-data'
HTGROUP='www-data'
NGINX_CONF='/etc/nginx/sites-available/nextcloud'
PHP_VERSION=`php -v | grep -oP "PHP \K[0-9]+\.[0-9]+"`
PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"
PHP_CONF="/etc/php/$PHP_VERSION/fpm/pool.d/www.conf"
PGSQL_PASSWORD=$(tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w "64" | head -n 1)
REDIS_CONF='/etc/redis/redis.conf'

# Download Nextcloud
sudo wget -q --show-progress -T 10 -t 2 "${NCREPO}/${STABLEVERSION}.tar.bz2" -P "$HTML"
sudo tar -xjf "${HTML}/${STABLEVERSION}.tar.bz2" -C "${HTML}"
sudo rm "${HTML}/${STABLEVERSION}.tar.bz2"

# Update permissions
sudo chown -R ${HTUSER}:${HTGROUP} ${NCPATH} -R

# Stop services
sudo service nginx stop
sudo service php${PHP_VERSION}-fpm stop

# Configure OpenSSL
sudo mkdir -p /etc/ssl/nginx/
sudo openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout /etc/ssl/nginx/${NCDOMAIN}.key -out /etc/ssl/nginx/${NCDOMAIN}.crt
sudo openssl dhparam -out /etc/ssl/nginx/${NCDOMAIN}.pem 4096

# Configure nginx
TEMP=$(mktemp)
cat <<CONFIG_NGINX > ${TEMP}
upstream php-handler {
    #server 127.0.0.1:9000;
    server unix:/run/php/php${PHP_VERSION}-fpm.sock;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${NCDOMAIN};
    # enforce https
    return 301 https://\$server_name:443\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${NCDOMAIN};

    # Use Mozilla's guidelines for SSL/TLS settings
    # https://mozilla.github.io/server-side-tls/ssl-config-generator/
    # NOTE: some settings below might be redundant
    ssl_certificate /etc/ssl/nginx/${NCDOMAIN}.crt;
    ssl_certificate_key /etc/ssl/nginx/${NCDOMAIN}.key;

    # Add headers to serve security related headers
    # Before enabling Strict-Transport-Security headers please read into this
    # topic first.
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;";
    #
    # WARNING: Only add the preload option once you read about
    # the consequences in https://hstspreload.org/. This option
    # will add the domain to a hardcoded list that is shipped
    # in all major browsers and getting removed from this list
    # could take several months.
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;
    add_header Referrer-Policy no-referrer;
    add_header X-Frame-Options "SAMEORIGIN";

    # Remove X-Powered-By, which is an information leak
    fastcgi_hide_header X-Powered-By;
    
    # Path to the root of your installation
    root /var/www/nextcloud;

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # The following 2 rules are only needed for the user_webfinger app.
    # Uncomment it if you're planning to use this app.
    #rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
    #rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;

    # The following rule is only needed for the Social app.
    # Uncomment it if you're planning to use this app.
    #rewrite ^/.well-known/webfinger /public.php?service=webfinger last;

    location = /.well-known/carddav {
      return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    location = /.well-known/caldav {
      return 301 \$scheme://\$host:\$server_port/remote.php/dav;
    }
    
    # set max upload size
    client_max_body_size 16G;
    fastcgi_buffers 64 4K;

    # Enable gzip but do not remove ETag headers
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    # Uncomment if your server is build with the ngx_pagespeed module
    # This module is currently not supported.
    #pagespeed off;

    location / {
        rewrite ^ /index.php\$uri;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ {
        deny all;
    }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }

    location ~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|oc[ms]-provider/.+)\.php(?:\$|/) {
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
        # Avoid sending the security headers twice
        fastcgi_param modHeadersAvailable true;
        # Enable pretty urls
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~ ^/(?:updater|oc[ms]-provider)(?:\$|/) {
        try_files \$uri/ =404;
        index index.php;
    }

    # Adding the cache control header for js, css and map files
    # Make sure it is BELOW the PHP block
    location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463";
        # Add headers to serve security related headers (It is intended to
        # have those duplicated to the ones above)
        # Before enabling Strict-Transport-Security headers please read into
        # this topic first.
        #add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;";
        #
        # WARNING: Only add the preload option once you read about
        # the consequences in https://hstspreload.org/. This option
        # will add the domain to a hardcoded list that is shipped
        # in all major browsers and getting removed from this list
        # could take several months.
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Robots-Tag none;
        add_header X-Download-Options noopen;
        add_header X-Permitted-Cross-Domain-Policies none;
        add_header Referrer-Policy no-referrer;
        add_header X-Frame-Options "SAMEORIGIN";

        # Optional: Don't log access to assets
        access_log off;
    }

    location ~ \.(?:png|html|ttf|ico|jpg|jpeg)$ {
        try_files \$uri /index.php\$request_uri;
        # Optional: Don't log access to other assets
        access_log off;
    }

    # Intermediate config from ssl-config.mozilla.org
    # TLSv1.2 for 100 score on Protocol Support
    ssl_protocols TLSv1.2;
    
    # Cipher type and order from acunetix.com
    # Ciphers >= 256 bits for 100 score on Cipher Strength
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    
    # 'on' is recommended by Acunetix, but lowers SSL Labs score to 90
    ssl_prefer_server_ciphers off;

    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Let's Encrypt
    location ~ /.well-known/acme-challenge {
      allow all;
    }
}
CONFIG_NGINX
sudo cp ${TEMP} ${NGINX_CONF}
sudo chmod 644 ${NGINX_CONF}
rm -f ${TEMP}
unset TEMP
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -s ${NGINX_CONF} /etc/nginx/sites-enabled/nextcloud

# Configure PostgreSQL
sudo -u postgres psql -c "CREATE USER nextcloud WITH PASSWORD '${PGSQL_PASSWORD}';"
sudo -u postgres psql -c "CREATE DATABASE nextcloud TEMPLATE template0 ENCODING 'UNICODE';"
sudo -u postgres psql -c "ALTER DATABASE nextcloud OWNER TO nextcloud;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;"

# Configure PHP
sudo sed -i "s|;env|env|g" ${PHP_CONF}
sudo sed -i "s|;opcache.enable=0|opcache.enable=1|g" ${PHP_INI}
sudo sed -i "s|;opcache.enable_cli=0|opcache.enable_cli=1|g" ${PHP_INI}
sudo sed -i "s|;opcache.memory_consumption=64|opcache.memory_consumption=128|g" ${PHP_INI}
sudo sed -i "s|;opcache.interned_strings_buffer=4|opcache.interned_strings_buffer=8|g" ${PHP_INI}
sudo sed -i "s|;opcache.max_accelerated_files=2000|opcache.max_accelerated_files=10000|g" ${PHP_INI}
sudo sed -i "s|;opcache.revalidate_freq=2|opcache.revalidate_freq=1|g" ${PHP_INI}
sudo sed -i "s|;opcache.save_comments=1|opcache.save_comments=1|g" ${PHP_INI}

# Configure Redis
sudo sed -i "s|# unixsocket|unixsocket|g" ${REDIS_CONF}
sudo sed -i "s|unixsocketperm .*|unixsocketperm 775|g" ${REDIS_CONF}
sudo sed -i "s|^port.*|port 0|g" ${REDIS_CONF}
sudo chown redis:root ${REDIS_CONF}
sudo chmod 600 ${REDIS_CONF}
sudo usermod -a -G redis ${HTUSER}
sudo service redis-server restart

# Start Nextcloud
sudo service php${PHP_VERSION}-fpm start
sudo service nginx start

# Display database configuration information
echo "Configure the database"
echo "Database user: nextcloud"
echo "Database password: ${PGSQL_PASSWORD}"
echo "Database name: nextcloud"
echo

# Prompt user to create credentials for their Nextcloud Web interface
while true
do
    read -p "Enter an admin username for Nextcloud Web interface: " NCUSER
    read -p "Enter an admin password for Nextcloud Web interface: " NCPASS
    echo "Your Nextcloud Web interface username is: $NCUSER"
    echo "Your Nextcloud Web interface password is: $NCPASS"
    while true
    do
        read -p "Keep this username and password (y/n)?: " answer
        case $answer in
            [yY]* ) break 2;;
            [nN]* ) break 1;;
            * ) ;;
        esac
    done
done
read -n 1 -s -r -p "Press any key to continue"

# Install Nextcloud via command
cd ${NCPATH}
sudo -u www-data php occ  maintenance:install \
    --database "pgsql" \
    --database-name "nextcloud" \
    --database-user "nextcloud" \
    --database-pass "${PGSQL_PASSWORD}" \
    --admin-user "${NCUSER}" \
    --admin-pass "${NCPASS}"

# Stop services
sudo service nginx stop
sudo service php${PHP_VERSION}-fpm stop
sudo service redis-server stop

# Make directory for redis-server.sock and update permissions
sudo mkdir -p /var/run/redis/
sudo usermod -g www-data redis
sudo chown -R redis:www-data /var/run/redis

# Update Nextcloud config
TEMP=$(mktemp)
sudo cp --no-preserve=mode,ownership ${NCPATH}/config/config.php ${TEMP}
sudo sed -i "s|);||g" ${TEMP}
cat <<UPDATE_NCCONFIG >> ${TEMP}
  'memcache.local' => '\OC\Memcache\APCu',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'redis' => [
     'host'     => '/var/run/redis/redis-server.sock',
     'port'     => 0,
   ],
);
UPDATE_NCCONFIG
sudo cp --no-preserve=mode,ownership ${TEMP} ${NCPATH}/config/config.php
sudo sed -i '/^\s*$/d' ${NCPATH}/config/config.php
sudo sed -i "/^.*0 =>.*/a\      1 => '${NCDOMAIN}'," ${NCPATH}/config/config.php

# Restart services
sudo systemctl enable redis-server
sudo service redis-server start
sudo service php${PHP_VERSION}-fpm start
sudo service nginx start

# Let's Encrypt
sudo certbot --nginx --agree-tos --email ${EMAIL} -d ${NCDOMAIN}
sudo sed -i "s|#ssl_trusted_certificate /etc/letsencrypt|ssl_trusted_certificate /etc/letsencrypt|g" ${NGINX_CONF}

# Restart services
sudo service nginx stop
sudo service php${PHP_VERSION}-fpm stop
sudo service redis-server stop
sudo service redis-server start
sudo service php${PHP_VERSION}-fpm start
sudo service nginx start
