FROM php:7.3-fpm-alpine3.11

ARG PHALCON_VERSION=3.4.5
ARG PHALCON_EXT_PATH=php7/64bits

# Install packages and remove default server definition
RUN apk --no-cache add gnupg autoconf make g++ nginx supervisor zlib-dev icu-dev icu-libs librdkafka-dev linux-headers git \
    && rm /etc/nginx/conf.d/default.conf

# Install PHP ZIP
RUN apk add --no-cache zip libzip-dev

# Installs GD extension and the required libraries: 
RUN apk update && apk add --no-cache \
freetype-dev \
libpng-dev \
jpeg-dev \
libjpeg-turbo-dev

RUN docker-php-ext-configure gd \
--with-freetype-dir=/usr/lib/ \
--with-png-dir=/usr/lib/ \
--with-jpeg-dir=/usr/lib/ \
--with-gd \
&& docker-php-ext-install gd

# Install PHP extensions
RUN docker-php-ext-install bcmath exif pcntl intl zip

# Install PHP phalcon
RUN set -xe && \
        curl -LO https://github.com/phalcon/cphalcon/archive/v${PHALCON_VERSION}.tar.gz && \
        tar xzf ${PWD}/v${PHALCON_VERSION}.tar.gz && \
        docker-php-ext-install -j $(getconf _NPROCESSORS_ONLN) ${PWD}/cphalcon-${PHALCON_VERSION}/build/${PHALCON_EXT_PATH} && \
        rm -r \
            ${PWD}/v${PHALCON_VERSION}.tar.gz \
            ${PWD}/cphalcon-${PHALCON_VERSION}

# Install PHP Redis
RUN pecl install redis && docker-php-ext-enable redis

# Install rdkafka
RUN pecl install rdkafka && docker-php-ext-enable rdkafka

# Install PHP GRPC
RUN pecl install grpc && docker-php-ext-enable grpc

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Download Microsoft SQL Server Prerequisites
RUN curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_17.7.2.1-1_amd64.apk
RUN curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/mssql-tools_17.7.1.1-1_amd64.apk

# Verify ODBC Signatures
RUN curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_17.7.2.1-1_amd64.sig
RUN curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/mssql-tools_17.7.1.1-1_amd64.sig
RUN curl https://packages.microsoft.com/keys/microsoft.asc  | gpg --import -
RUN gpg --verify msodbcsql17_17.7.2.1-1_amd64.sig msodbcsql17_17.7.2.1-1_amd64.apk
RUN gpg --verify mssql-tools_17.7.1.1-1_amd64.sig mssql-tools_17.7.1.1-1_amd64.apk

# Install the ODBC packages
RUN apk add --allow-untrusted msodbcsql17_17.7.2.1-1_amd64.apk
RUN apk add --allow-untrusted mssql-tools_17.7.1.1-1_amd64.apk

# Set mssql-tools ENV variable to the PATH
ENV PATH "$PATH:/opt/mssql-tools/bin"
RUN echo $PATH

# Remove the ODBC packages
RUN rm msodbcsql17_17.7.2.1-1_amd64.apk \
    mssql-tools_17.7.1.1-1_amd64.apk \
    msodbcsql17_17.7.2.1-1_amd64.sig \
    mssql-tools_17.7.1.1-1_amd64.sig

# Install unixodbc-dev required for pecl
RUN apk add --allow-untrusted unixodbc-dev

# Install SQL Server Drivers
RUN pecl channel-update pecl.php.net
RUN pecl install sqlsrv-5.6.1 pdo_sqlsrv-5.6.1
RUN docker-php-ext-enable --ini-name 30-sqlsrv.ini sqlsrv
RUN docker-php-ext-enable --ini-name 35-pdo_sqlsrv.ini pdo_sqlsrv

# Install Xdebug
RUN pecl install xdebug
RUN docker-php-ext-enable --ini-name 30-xdebug.ini xdebug

# Configure nginx
COPY config/nginx.conf /etc/nginx/nginx.conf

# Configure PHP
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
COPY config/php.ini /usr/local/etc/php/conf.d/custom.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Setup document root
RUN mkdir -p /var/www/html

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R nobody.nobody /var/www/html && \
  chown -R nobody.nobody /run && \
  chown -R nobody.nobody /var/lib/nginx && \
  chown -R nobody.nobody /var/log/nginx

# Switch to use a non-root user from here on
USER root

# Add application
WORKDIR /var/www/html

# Add a volume so that the external source code can be hooked
VOLUME [ "/var/www/html" ]

# Expose the port nginx is reachable on
EXPOSE 8080

# Let supervisord start nginx & php-fpm
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
