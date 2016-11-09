FROM ubuntu:14.04
MAINTAINER Leonid Trytynichenko <leo@trytynichenko.com>

# Install the PHP, apache and mysql extensions
RUN apt-get update && apt-get install -y libpng12-dev \
    libjpeg-dev \
    mysql-common \
    curl \
    apache2 \
    php5 \
    php5-mysql \
    php5-mcrypt \
    mysql-client-5.6 \
    && rm -rf /var/lib/apt/lists/*

# Configure apache
RUN a2enmod rewrite \
    && service apache2 restart

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
	&& chmod +x wp-cli.phar \
	&& mv wp-cli.phar /usr/local/bin/wp

# Setup the Composer installer
RUN curl -o /tmp/composer-setup.php https://getcomposer.org/installer \
    && curl -o /tmp/composer-setup.sig https://composer.github.io/installer.sig \
    && php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }"

# Configure php
RUN touch /etc/php5/apache2/conf.d/upload-limit.ini \
    && echo "upload_max_filesize = 256M" >> /etc/php5/apache2/conf.d/upload-limit.ini \
    ** echo "post_max_size = 256M" >> /etc/php5/apache2/conf.d/upload-limit.ini \
    ** echo "file_uploads = On" >> /etc/php5/apache2/conf.d/upload-limit.ini \
    ** echo "memory_limit = 256M" >> /etc/php5/apache2/conf.d/upload-limit.ini \
    ** echo "max_execution_time = 600" >> /etc/php5/apache2/conf.d/upload-limit.ini

COPY run.sh /
COPY 000-default.conf /etc/apache2/sites-enabled/
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]