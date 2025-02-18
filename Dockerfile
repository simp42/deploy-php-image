### ---------------------------base--------------------------------------
### Build the base Debian image that will be used in every other image
FROM debian:bullseye-slim as base

RUN ls -l $(which dpkg-split) && ls -l $(which dpkg-deb)
RUN for item in dpkg-split dpkg-deb; do \
  if [ ! -f /usr/sbin/$item ]; then \
    ln -sf /usr/bin/$item /usr/sbin/$item; \
  fi; \
done
RUN for item in tar rm; do \
  if [ ! -f /usr/sbin/$item ]; then \
    ln -sf /bin/$item /usr/sbin/$item; \
  fi; \
done

RUN ls -l /usr/sbin/dpkg-split /usr/sbin/dpkg-deb /usr/sbin/tar /usr/sbin/rm

RUN apt-get -qq update
RUN apt-get -qq install --no-install-recommends --no-install-suggests -y \
    apt-transport-https \
    ca-certificates \
    bzip2 \
    curl \
    git \
    gnupg \
    less \
    lsb-release \
    procps \
    tree \
    vim \
    wget
#END base

### ---------------------------deploy-php-image-base--------------------------------------
FROM base AS deploy-php-image-base
ARG PHP_DEFAULT_VERSION="7.4"
#ENV PHP_VERSIONS="php5.6 php7.0 php7.1 php7.2 php7.3 php7.4 php8.0 php8.1"
ENV PHP_VERSIONS="php7.2 php7.3 php7.4 php8.0 php8.1"
ENV PHP_INI=/etc/php/$PHP_DEFAULT_VERSION/fpm/php.ini
# composer normally screams about running as root, we don't need that.
ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_PROCESS_TIMEOUT 2000

# TARGETPLATFORM is Docker buildx's target platform (e.g. linux/arm64), while
# BUILDPLATFORM is the platform of the build host (e.g. linux/amd64)
ARG TARGETPLATFORM
ARG BUILDPLATFORM

SHELL ["/bin/bash", "-c"]

RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list && apt-get update
RUN curl -sSL --fail https://deb.nodesource.com/setup_14.x | bash -

RUN apt-get -qq update
RUN apt-get -qq install --no-install-recommends --no-install-suggests -y \
    ghostscript \
    imagemagick \
    mariadb-client \
    msmtp \
    nodejs \
    php-uploadprogress \
    sqlite3 \
    unzip \
    openssh-client \
    rsync \
    patch

RUN npm config set unsafe-perm true && npm install --global gulp-cli yarn

# The number of permutations of php packages available on each architecture because
# too much to handle, so has been codified here instead of in obscure logic
ENV php56_amd64="apcu bcmath bz2 curl cli common fpm gd imagick intl json ldap mbstring mcrypt memcached mysql opcache pgsql readline redis soap sqlite3 uploadprogress xdebug xhprof xml xmlrpc zip"
ENV php56_arm64="apcu bcmath bz2 curl cli common fpm gd imagick intl json ldap mbstring mcrypt mysql opcache pgsql readline soap sqlite3 uploadprogress xdebug xml xhprof xmlrpc zip"
ENV php70_amd64="apcu apcu-bc bcmath bz2 curl cli common fpm gd imagick intl json ldap mbstring mcrypt memcached mysql opcache pgsql readline redis soap sqlite3 uploadprogress xdebug xhprof xml xmlrpc zip"
ENV php70_arm64=$php70_amd64
ENV php71_amd64=$php70_amd64
ENV php71_arm64=$php70_arm64
ENV php72_amd64="apcu apcu-bc bcmath bz2 curl cli common fpm gd imagick intl json ldap mbstring memcached mysql opcache pgsql readline redis soap sqlite3 uploadprogress xdebug xhprof xml xmlrpc zip"
ENV php72_arm64=$php72_amd64
ENV php73_amd64=$php72_amd64
ENV php73_arm64=$php72_arm64
ENV php74_amd64="apcu apcu-bc bcmath bz2 curl cli common fpm gd imagick intl json ldap mbstring memcached mysql opcache pgsql readline redis soap sqlite3 uploadprogress xdebug xhprof xml xmlrpc zip"
ENV php74_arm64=$php74_amd64

# As of php8.0 json is now part of core package and xmlrpc has been removed from PECL
ENV php80_amd64="apcu bcmath bz2 curl cli common fpm gd imagick intl ldap mbstring memcached mysql opcache pgsql readline redis soap sqlite3 uploadprogress xdebug xhprof xml xmlrpc zip"
ENV php80_arm64=$php80_amd64

ENV php81_amd64="bcmath bz2 curl cli common fpm gd intl ldap mbstring mysql opcache pgsql readline soap sqlite3 xml zip"
ENV php81_arm64=$php81_amd64

RUN for v in $PHP_VERSIONS; do \
    targetarch=${TARGETPLATFORM#linux/}; \
    pkgvar=${v//.}_${targetarch}; \
    pkgs=$(echo ${!pkgvar} | awk -v v="$v" ' BEGIN {RS=" "; }  { printf "%s-%s ",v,$0 ; }' ); \
    [[ ${pkgs// } != "" ]] && (apt-get -qq install --no-install-recommends --no-install-suggests -y $pkgs || exit $?) \
done
RUN phpdismod xhprof uploadprogress && \
    apt-get -qq autoremove -y && \
  	update-alternatives --set php /usr/bin/php${PHP_DEFAULT_VERSION} && \
    ln -sf /usr/sbin/php-fpm${PHP_DEFAULT_VERSION} /usr/sbin/php-fpm && \
    mkdir -p /run/php && chown -R www-data:www-data /run
ADD image-files /

#END deploy-php-image-base

### ---------------------------deploy-php-image--------------------------------------
FROM deploy-php-image-base AS deploy-php-image

ARG JENKINS_USER_ID=110
ARG JENKINS_GROUP_ID=117
ARG JENKINS_HOME=/home/jenkins

RUN groupadd -g $JENKINS_GROUP_ID jenkins && \
    useradd -u $JENKINS_USER_ID -s /bin/sh -g $JENKINS_GROUP_ID jenkins

RUN curl -o /usr/local/bin/composer1 -sSL https://getcomposer.org/download/latest-1.x/composer.phar && \
    chmod 0755 /usr/local/bin/composer1 && \
    curl -o /usr/local/bin/composer2 -sSL https://getcomposer.org/composer-stable.phar && \
    chmod 0755 /usr/local/bin/composer2 && \
    ln -s /usr/local/bin/composer2 /usr/local/bin/composer

RUN mkdir -p "$JENKINS_HOME/.cache" && \
    chown -R $JENKINS_USER_ID:$JENKINS_GROUP_ID "$JENKINS_HOME"

RUN apt-get -qq autoremove && apt-get -qq clean -y && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/n && \
    npm install n -g bower gulp && \
    chown -R $JENKINS_USER_ID:$JENKINS_GROUP_ID /usr/local/n && \
    # make sure the required folders exist (safe to execute even if they already exist)
    mkdir -p /usr/local/bin /usr/local/lib /usr/local/include /usr/local/share && \
    chown -R $JENKINS_USER_ID:$JENKINS_GROUP_ID /usr/local/bin /usr/local/lib /usr/local/include /usr/local/share

#END deploy-php-image \