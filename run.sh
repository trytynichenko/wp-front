#!/bin/bash
set +e


# WordPress env
# -------------
WP_WEBSITE_URL=${WP_WEBSITE_URL:-"wp.com"}
WP_WEBSITE_DUMP_URL=${WP_WEBSITE_DUMP_URL:-"false"}
WP_WEBSITE_PORT=${WP_WEBSITE_PORT:-"8080"}
WP_WEBSITE_VER=${WP_WEBSITE_VER:-"latest"}
WP_WEBSITE_ADMIN_EMAIL=${WP_WEBSITE_ADMIN_EMAIL:-"admin@${WP_WEBSITE_URL}"}

WP_WEBSITE_DEBUG=${WP_WEBSITE_DEBUG:-"false"}
WP_WEBSITE_DEBUG_LOG=${WP_WEBSITE_DEBUG_LOG:-"false"}
WP_WEBSITE_CACHE=${WP_WEBSITE_CACHE:-"false"}

WP_WEBSITE_DB_HOST=${WP_WEBSITE_DB_HOST:-"mysql"}
WP_WEBSITE_DB_USER=${WP_WEBSITE_DB_USER:-"root"}
WP_WEBSITE_DB_NAME=${WP_WEBSITE_DB_NAME:-"wp"}


# PHP env
# -------------
WP_PHP_MEMORY_LIMIT=${WP_PHP_MEMORY_LIMIT:-"128M"}
WP_PHP_FILE_UPLOADS=${WP_PHP_FILE_UPLOADS:-"On"}
WP_PHP_UPLOAD_MAX_FILESIZE=${WP_PHP_UPLOAD_MAX_FILESIZE:-"128M"}
WP_PHP_POST_MAX_SIZE=${WP_PHP_POST_MAX_SIZE:-"300M"}
WP_PHP_MAX_EXECUTION_TIME=${WP_PHP_MAX_EXECUTION_TIME:-"128M"}


# MySQL env
# ---------
MYSQL_PORT=${MYSQL_PORT:-"3306"}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"root"}

MYSQL_WAIT_LOOPS=${MYSQL_WAIT_LOOPS:-"10"}
MYSQL_WAIT_SLEEP=${MYSQL_WAIT_SLEEP:-"5"}


# Status functions
# ----------------
SUCCESS () { echo -e "\n$(tput -T xterm setaf 2)$(tput -T xterm bold)SUCCESS$(tput -T xterm sgr 0): $1"; }
INFO () { echo -e "\n$(tput -T xterm setaf 3)$(tput -T xterm bold)INFO$(tput -T xterm sgr 0): $1"; }
ERROR () { echo -e "\n$(tput -T xterm setaf 1)$(tput -T xterm bold)ERROR$(tput -T xterm sgr 0): $1"; }


# Set permission
# --------------
INFO "Set up root folder permission..."
    chown -R www-data:www-data /var/www/html
SUCCESS "Folder permission successfully configured!"


# Configure wp-cli
# ----------------
INFO "Configure WP-CLI config file based on ENV..."
    sed -i -e "s/{{WP_WEBSITE_URL}}/${WP_WEBSITE_URL}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_DB_USER}}/${WP_WEBSITE_DB_USER}/g" ./wp-cli.yml
    sed -i -e "s/{{MYSQL_ROOT_PASSWORD}}/${MYSQL_ROOT_PASSWORD}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_DB_NAME}}/${WP_WEBSITE_DB_NAME}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_DB_HOST}}/${WP_WEBSITE_DB_HOST}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_DEBUG}}/${WP_WEBSITE_DEBUG}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_DEBUG_LOG}}/${WP_WEBSITE_DEBUG_LOG}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_CACHE}}/${WP_WEBSITE_CACHE}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_PORT}}/${WP_WEBSITE_PORT}/g" ./wp-cli.yml
    sed -i -e "s/{{WP_WEBSITE_ADMIN_EMAIL}}/${WP_WEBSITE_ADMIN_EMAIL}/g" ./wp-cli.yml
SUCCESS "WP-CLI config successfully configured!"


# Download WordPress core
# -----------------------
if [ ! -f /var/www/html/public/wp-settings.php ]; then
    INFO "Downloading WordPress core..."
    wp core download --force \
    --version=${WP_WEBSITE_VER} \
    --skip-plugins=all \
    --skip-themes=all \
    --allow-root >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SUCCESS "WordPress core successfully downloaded!"
    else
        ERROR "Failed to download WordPress core"
    fi
else
    INFO "WordPress core already downloaded! Skipping..."
fi


# Wait for MySQL
# --------------
INFO "Waiting for MySQL to initialize..."
i=0
while ! nc ${WP_WEBSITE_DB_HOST} ${MYSQL_PORT} >/dev/null 2>&1 < /dev/null; do
  i=`expr $i + 1`
  if [ $i -ge ${MYSQL_WAIT_LOOPS} ]; then
    echo "$(date) - ${WP_WEBSITE_DB_HOST}:${MYSQL_PORT} still not reachable, try to increase MYSQL_WAIT_LOOPS environment more than '${MYSQL_WAIT_LOOPS}'"
    exit 1
  fi
  echo "$(date) - waiting for ${WP_WEBSITE_DB_HOST}:${MYSQL_PORT}..."
  sleep ${MYSQL_WAIT_SLEEP}
done
SUCCESS "MySQL ready!"


# Generate wp-config.php file
# ---------------------------
INFO "Generate wp-config.php file..."
rm -f /var/www/html/public/wp-config.php
sudo -u www-data wp core config >/dev/null 2>&1
if [ $? -eq 0 ]; then
    SUCCESS "Config file successfully generated!"
else
    ERROR "Could not generate wp-config.php file"
fi


# Setup database
# --------------
INFO "Create database '${WP_WEBSITE_DB_NAME}'"
if [ ! "$(wp core is-installed --allow-root >/dev/null 2>&1 && echo $?)" ]; then
    INFO "Database backup was not loaded. Initializing new database... "
    sudo -u www-data wp db create >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SUCCESS "New database successfully created!"
        INFO "Trying install WordPress core..."
        sudo -u www-data wp core install >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            SUCCESS "WordPress core successfully installed!"
        else
            ERROR "Could not install WordPress core!"
        fi
    else
        ERROR "Initializing new database failed!"
    fi
else
    INFO "WordPress core already installed! Skipping..."
    if [ "${WP_WEBSITE_DUMP_URL}" != false ]; then
        INFO "Trying replace urls..."
        sudo -u www-data wp search-replace ${WP_WEBSITE_DUMP_URL} ${WP_WEBSITE_URL}:${WP_WEBSITE_PORT} --recurse-objects --skip-columns=guid >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            SUCCESS "URL's successfully replaced!"
        else
            ERROR "Could not replace ${WP_WEBSITE_DUMP_URL} to ${WP_WEBSITE_URL}:${WP_WEBSITE_PORT}"
        fi
    fi
fi


# Filesystem Permissions
# ----------------------
INFO "Adjusting filesystem permissions..."
    groupadd -f docker && usermod -aG docker www-data
    find /var/www/html/public -type d -exec chmod 755 {} \;
    find /var/www/html/public -type f -exec chmod 644 {} \;
    mkdir -p /var/www/html/public/wp-content/uploads
    chmod -R 775 /var/www/html/public/wp-content/uploads && \
        chown -R :docker /var/www/html/public/wp-content/uploads
SUCCESS "Adjusting permissions done!"


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
if [ -f /var/www/html/composer.json ]; then
    INFO "Install composer dependency..."
    composer install >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SUCCESS "Composer dependency successfully installed!"
    else
        ERROR "Could not install composer dependencies!"
    fi
else
    INFO "composer.json file not exist! Skipping..."
fi

# Configure .htaccess
# -------------------
if [ ! -f /var/www/html/public/.htaccess ]; then
    INFO "Generating .htaccess file..."
    wp rewrite flush --allow-root --hard >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        SUCCESS ".htaccess successfully created!"
    else
        ERROR "Could not generate .htaccess file"
    fi
else
    INFO ".htaccess exists! Skipping..."
fi


# Configure PHP
# ---------------------
INFO "Configure PHP..."
    sed -i -e "s/memory_limit = .*/memory_limit = ${WP_PHP_MEMORY_LIMIT}/" /etc/php5/apache2/php.ini
    sed -i -e "s/file_uploads = .*/file_uploads = ${WP_PHP_FILE_UPLOADS}/" /etc/php5/apache2/php.ini
    sed -i -e "s/upload_max_filesize = .*/upload_max_filesize = ${WP_PHP_UPLOAD_MAX_FILESIZE}/" /etc/php5/apache2/php.ini
    sed -i -e "s/post_max_size = .*/post_max_size = ${WP_PHP_POST_MAX_SIZE}/" /etc/php5/apache2/php.ini
    sed -i -e "s/max_execution_time = .*/max_execution_time = ${WP_PHP_MAX_EXECUTION_TIME}/" /etc/php5/apache2/php.ini
SUCCESS "PHP successfully Configured!"


# Configure VirtualHost
# ---------------------
INFO "Configure VirtualHost..."
    sed -i -e "s/{{HOST}}/${WP_WEBSITE_URL}/g" /etc/apache2/sites-enabled/000-default.conf
SUCCESS "VirtualHost successfully Configured!"


# Start apache
# ------------
INFO "Starting apache service..."
rm -f /var/run/apache2/apache2.pid
source /etc/apache2/envvars
exec apache2 -D FOREGROUND