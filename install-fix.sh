#!/bin/bash
set -e

# Define constants
EMAIL="spluigi@gmail.com"
NCDOMAIN="cloud.julesc.io"
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
REDIS_SOCK='/var/run/redis/redis.sock'

# # Stop services
# sudo service nginx stop
# sudo service php${PHP_VERSION}-fpm stop
# sudo service redis-server stop
#
# # Update Nextcloud config
# TEMP=$(mktemp)
# sudo cp --no-preserve=mode,ownership ${NCPATH}/config/config.php ${TEMP}
# sudo sed -i "s|);||g" ${TEMP}
# cat <<UPDATE_NCCONFIG >> ${TEMP}
#   'memcache.locking' => '\\OC\\Memcache\\Redis',
#   'memcache.local' => '\\OC\\Memcache\\Redis',
#   'redis' =>
#   array (
#     'host' => '${REDIS_SOCK}',
#     'port' => 0,
#   ),
# );
# UPDATE_NCCONFIG
# sudo cp --no-preserve=mode,ownership ${TEMP} ${NCPATH}/config/config.php
# sed -i '/^\s*$/d' ${NCPATH}/config/config.php
#
# # Restart services
# sudo systemctl enable redis-server
# sudo service redis-server start
# sudo service php${PHP_VERSION}-fpm start
# sudo service nginx start
#
# # Let's Encrypt
# sudo certbot --nginx --agree-tos --email ${EMAIL} -d ${NCDOMAIN}
# sed -i "s|ssl_certificate /etc/ssl|#ssl_certificate /etc/ssl|g" ${NGINX_CONF}
# sed -i "s|ssl_certificate_key /etc/ssl|#ssl_certificate_key /etc/ssl|g" ${NGINX_CONF}
# sed -i "s|#ssl_certificate /etc/letsencrypt|ssl_certificate /etc/letsencrypt|g" ${NGINX_CONF}
# sed -i "s|#ssl_certificate_key /etc/letsencrypt|ssl_certificate_key /etc/letsencrypt|g" ${NGINX_CONF}
sed -i "s|#ssl_trusted_certificate /etc/letsencrypt|ssl_trusted_certificate /etc/letsencrypt|g" ${NGINX_CONF}

# Restart services
sudo service nginx stop
sudo service php${PHP_VERSION}-fpm stop
sudo service redis-server stop
sudo service redis-server start
sudo service php${PHP_VERSION}-fpm start
sudo service nginx start
