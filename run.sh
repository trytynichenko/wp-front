#!/bin/bash
set -e


# WordPress env
# ------------
WP_WEBSITE_URL=${WP_WEBSITE_URL:-'wp.com'}
WP_WEBSITE_VER=${WP_WEBSITE_VER:-'latest'}
WP_WEBSITE_DEBUG=${WP_WEBSITE_DEBUG:-'false'}
WP_WEBSITE_DEBUG_LOG=${WP_WEBSITE_DEBUG_LOG:-'false'}
WP_WEBSITE_DB_HOST=${WP_WEBSITE_DB_HOST:-'mysql'}
WP_WEBSITE_DB_USER=${WP_WEBSITE_DB_USER:-'root'}
WP_WEBSITE_DB_NAME=${WP_DB_NAME:-'wp'}
WP_WEBSITE_ADMIN_EMAIL=${WP_WEBSITE_ADMIN_EMAIL:-'admin@${WP_WEBSITE_URL}'}


# MySQL env
# ------------
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-'root'}


SUCCESS () {
  echo -e "\n$(tput -T xterm setaf 2)$(tput -T xterm bold)SUCCESS$(tput -T xterm sgr 0): $1";
}

INFO () {
  echo -e "\n$(tput -T xterm setaf 3)$(tput -T xterm bold)INFO$(tput -T xterm sgr 0): $1";
}


# Composer installation
# ------------
INFO "Install composer..."
    php /tmp/composer-setup.php \
    --no-ansi \
    --install-dir=/usr/local/bin \
    --filename=composer \
    && rm -rf /tmp/composer-setup.php
SUCCESS "Composer installed!"


# Download WordPress core
# ------------
INFO "Downloading WordPress core..."
if [ ! "$(wp core is-installed --allow-root >/dev/null 2>&1 && echo $?)" ]; then
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
# --------------
INFO "Generate wp-config.php..."
if [ ! "$(wp core is-installed --allow-root >/dev/null 2>&1 && echo $?)" ]; then
    wp core config \
    --allow-root \
    --path=/var/www/${WP_WEBSITE_URL}/public \
    --dbname=${WP_WEBSITE_DB_NAME} \
    --dbuser=${WP_WEBSITE_DB_USER} \
    --dbpass=${MYSQL_ROOT_PASSWORD} \
    --dbhost=${WP_WEBSITE_DB_HOST} \
    --extra-php <<PHP
define( 'WP_DEBUG', ${WP_WEBSITE_DEBUG} );
define( 'WP_DEBUG_LOG', true );
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


# Start apache
# ------------
INFO "=> Starting apache service... "
rm -f /var/run/apache2/apache2.pid
source /etc/apache2/envvars
exec apache2 -D FOREGROUND