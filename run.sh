#!/bin/bash
set -e


# WordPress env
# -------------
WP_WEBSITE_URL=${WP_WEBSITE_URL:-'wp.com'}
WP_WEBSITE_VER=${WP_WEBSITE_VER:-'latest'}
WP_WEBSITE_DEBUG=${WP_WEBSITE_DEBUG:-'false'}
WP_WEBSITE_DEBUG_LOG=${WP_WEBSITE_DEBUG_LOG:-'false'}
WP_WEBSITE_DB_HOST=${WP_WEBSITE_DB_HOST:-'mysql'}
WP_WEBSITE_DB_USER=${WP_WEBSITE_DB_USER:-'root'}
WP_WEBSITE_DB_NAME=${WP_WEBSITE_DB_NAME:-'wp'}
WP_WEBSITE_CACHE==${WP_WEBSITE_CACHE:-'false'}
WP_WEBSITE_MEMORY_LIMMIT==${WP_WEBSITE_MEMORY_LIMMIT:-'128M'}
WP_WEBSITE_ADMIN_EMAIL=${WP_WEBSITE_ADMIN_EMAIL:-'admin@${WP_WEBSITE_URL}'}


# MySQL env
# ---------
MYSQL_HOST=${MYSQL_HOST:-'3306'}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-'root'}
MYSQL_WAIT_LOOPS=${MYSQL_WAIT_LOOPS:-'10'}
MYSQL_WAIT_SLEEP=${MYSQL_WAIT_SLEEP:-'5'}

SUCCESS () {
  echo -e "\n$(tput -T xterm setaf 2)$(tput -T xterm bold)SUCCESS$(tput -T xterm sgr 0): $1";
}

INFO () {
  echo -e "\n$(tput -T xterm setaf 3)$(tput -T xterm bold)INFO$(tput -T xterm sgr 0): $1";
}


# Wait for MySQL
# --------------
INFO "Waiting for MySQL to initialize..."
i=0
while ! nc ${WP_WEBSITE_DB_HOST} ${MYSQL_HOST} >/dev/null 2>&1 < /dev/null; do
  i=`expr $i + 1`
  if [ $i -ge ${MYSQL_WAIT_LOOPS} ]; then
    echo "$(date) - ${WP_WEBSITE_DB_HOST}:${MYSQL_HOST} still not reachable, giving up"
    exit 1
  fi
  echo "$(date) - waiting for ${WP_WEBSITE_DB_HOST}:${MYSQL_HOST}..."
  sleep ${MYSQL_WAIT_SLEEP}
done
SUCCESS "MySQL ready!"


# Download WordPress core
# -----------------------
INFO "Downloading WordPress core..."
if [ ! "$(wp core is-installed --allow-root --path=/var/www/${WP_WEBSITE_URL}/public >/dev/null 2>&1 && echo $?)" ]; then
    wp core download \
    --allow-root \
    --path=/var/www/${WP_WEBSITE_URL}/public \
    --skip-plugins=all \
    --skip-themes=all \
    --version=${WP_WEBSITE_VER}
    SUCCESS "WordPress core successfully downloaded!"
else
    INFO "WordPress core already exist!"
fi


# Generate wp-config.php file
# ---------------------------
INFO "Generate wp-config.php..."
if [ ! "$(wp core is-installed --allow-root --path=/var/www/${WP_WEBSITE_URL}/public >/dev/null 2>&1 && echo $?)" ]; then
    wp core config \
    --allow-root \
    --path=/var/www/${WP_WEBSITE_URL}/public \
    --dbname=${WP_WEBSITE_DB_NAME} \
    --dbuser=${WP_WEBSITE_DB_USER} \
    --dbpass=${MYSQL_ROOT_PASSWORD} \
    --dbhost=${WP_WEBSITE_DB_HOST} \
    --extra-php <<PHP
define( 'WP_DEBUG', ${WP_WEBSITE_DEBUG} );
define( 'WP_DEBUG_LOG', ${WP_WEBSITE_DEBUG_LOG} );
define( 'WP_CACHE', ${WP_WEBSITE_CACHE} );
PHP
    SUCCESS "Config file successfully generated!"
else
    INFO "Already exists!"
fi


# Setup database
# --------------
INFO "Create database '${WP_WEBSITE_DB_NAME}'"
if [ ! "$(wp core is-installed --allow-root --path=/var/www/${WP_WEBSITE_URL}/public >/dev/null 2>&1 && echo $?)" ]; then
    wp db create --allow-root \
    --path=/var/www/${WP_WEBSITE_URL}/public
    SUCCESS "Database successfully created!"
else
    INFO "Already exists!"
fi


# Filesystem Permissions
# ----------------------
INFO "Adjusting filesystem permissions... "
groupadd -f docker && usermod -aG docker www-data
find /var/www/${WP_WEBSITE_URL}/public -type d -exec chmod 755 {} \;
find /var/www/${WP_WEBSITE_URL}/public -type f -exec chmod 644 {} \;
mkdir -p /var/www/${WP_WEBSITE_URL}/public/wp-content/uploads
chmod -R 775 /var/www/${WP_WEBSITE_URL}/public/wp-content/uploads && \
    chown -R :docker /var/www/${WP_WEBSITE_URL}/public/wp-content/uploads
SUCCESS "Done!"


# Composer installation
# ---------------------
INFO "Install composer..."
    php /tmp/composer-setup.php \
    --no-ansi \
    --install-dir=/usr/local/bin \
    --filename=composer \
    && rm -rf /tmp/composer-setup.php
SUCCESS "Composer installed!"


# Run composer
# ------------
if [ -f /var/www/${WP_WEBSITE_URL}/composer.json ]; then
    INFO "Install composer dependency... "
    cd /var/www/${WP_WEBSITE_URL}/ && composer install
    SUCCESS "Composer dependency successfully installed!"
fi


# Configure .htaccess
# -------------------
if [ ! -f /var/www/${WP_WEBSITE_URL}/public/.htaccess ]; then
  INFO "Generating .htaccess file... "
  wp rewrite flush --allow-root \
  --hard \
  --path=/var/www/${WP_WEBSITE_URL}/public
  SUCCESS ".htaccess successfully created!"
else
  INFO ".htaccess exists"
fi


# Configure PHP
# ---------------------
INFO "Configure PHP... "
sed -i -e "s/memory_limit = .*/memory_limit = ${WP_WEBSITE_MEMORY_LIMMIT}/" /etc/php5/apache2/php.ini
SUCCESS "PHP successfully Configured!"


# Configure VirtualHost
# ---------------------
INFO "Configure VirtualHost... "
sed -i -e "s/{HOST}/${WP_WEBSITE_URL}/g" /etc/apache2/sites-enabled/000-default.conf
SUCCESS "VirtualHost successfully Configured!"


# Start apache
# ------------
INFO "=> Starting apache service... "
rm -f /var/run/apache2/apache2.pid
source /etc/apache2/envvars
exec apache2 -D FOREGROUND