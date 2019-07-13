#!/bin/bash

DISTRO=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$VERSION_ID" = "8" ]; then
        DISTRO="jessie"
    else
        if [ "$VERSION_ID" = "9" ]; then
            DISTRO="stretch"
        fi
    fi
fi

function initsystem () {
    # create hostname
    HOST=`grep $APPHOSTNAME /etc/hosts`
    if [ "$HOST" == "" ]; then
        echo "127.0.0.1 $APPHOSTNAME $APPHOSTNAME2" >> /etc/hosts
    fi
    hostname $APPHOSTNAME
    echo "$APPHOSTNAME" > /etc/hostname

    # local time
    echo "Europe/Paris" > /etc/timezone
    cp /usr/share/zoneinfo/Europe/Paris /etc/localtime
    locale-gen fr_FR.UTF-8
    update-locale LC_ALL=fr_FR.UTF-8

    # install all packages
    apt-get install -y software-properties-common apt-transport-https

    if [ "$DISTRO" == "stretch" ]; then
        apt-get install -y dirmngr
    fi

    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php $DISTRO main" > /etc/apt/sources.list.d/sury_php.list

    if [ "$DISTRO" == "stretch" ]; then
        if [ ! -f "/etc/apt/sources.list.d/mysql.list" ]; then
            echo -e "deb http://repo.mysql.com/apt/debian/ stretch mysql-$MYSQL_VERSION\ndeb-src http://repo.mysql.com/apt/debian/ stretch mysql-$MYSQL_VERSION" > /etc/apt/sources.list.d/mysql.list
            wget -O /tmp/RPM-GPG-KEY-mysql https://repo.mysql.com/RPM-GPG-KEY-mysql
            apt-key add /tmp/RPM-GPG-KEY-mysql
        fi
    fi

    apt-get update
    apt-get -y upgrade
    apt-get -y install debconf-utils
    export DEBIAN_FRONTEND=noninteractive
    echo "mysql-server-$MYSQL_VERSION mysql-community-server/root_password password jelix" | debconf-set-selections
    echo "mysql-server-$MYSQL_VERSION mysql-community-server/root_password_again password jelix" | debconf-set-selections
    echo "mysql-community-server mysql-community-server/root_password password jelix" | debconf-set-selections
    echo "mysql-community-server mysql-community-server/root_password_again password jelix" | debconf-set-selections

    apt-get -y install nginx
    apt-get -y install  php${PHP_VERSION}-fpm \
                        php${PHP_VERSION}-cli \
                        php${PHP_VERSION}-curl \
                        php${PHP_VERSION}-gd \
                        php${PHP_VERSION}-intl \
                        php${PHP_VERSION}-ldap \
                        php${PHP_VERSION}-mysql \
                        php${PHP_VERSION}-pgsql \
                        php${PHP_VERSION}-sqlite3 \
                        php${PHP_VERSION}-soap \
                        php${PHP_VERSION}-dba \
                        php${PHP_VERSION}-xml \
                        php${PHP_VERSION}-mbstring \
                        php-memcached \
                        php-redis

    if [ "$PHP_VERSION" != "7.3" ]; then
        #not compatible with 7.3
        apt-get -y install php-memcache
    fi

    apt-get -y install mysql-server mysql-client
    apt-get -y install git vim unzip curl

    # create a database into mysql + users
    if [ ! -d /var/lib/mysql/$APPNAME/ ]; then
        echo "setting mysql database.."
        mysql -u root -pjelix -e "CREATE DATABASE IF NOT EXISTS $APPNAME CHARACTER SET utf8;CREATE USER test_user IDENTIFIED BY 'jelix';GRANT ALL ON $APPNAME.* TO test_user;FLUSH PRIVILEGES;"
    fi

    sed -i -- s/bind-address\s+127\.0\.0\.1/bind-address 0.0.0.0/g /etc/mysql/my.cnf

    # install default vhost for apache
    cp $VAGRANTDIR/jelixapp/vhost /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- s/__APPHOSTNAME__/$APPHOSTNAME/g /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- s/__APPHOSTNAME2__/$APPHOSTNAME2/g /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- "s!__APPDIR__!$APPDIR!g" /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- "s!__ROOTDIR__!$ROOTDIR!g" /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- s/__APPNAME__/$APPNAME/g /etc/nginx/sites-available/$APPNAME.conf
    sed -i -- s/__FPM_SOCK__/$FPM_SOCK/g /etc/nginx/sites-available/$APPNAME.conf

    if [ ! -f /etc/nginx/sites-enabled/010-$APPNAME.conf ]; then
        ln -s /etc/nginx/sites-available/$APPNAME.conf /etc/nginx/sites-enabled/010-$APPNAME.conf
    fi
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        rm -f "/etc/nginx/sites-enabled/default"
    fi

    sed -i "/^user = www-data/c\user = vagrant" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
    sed -i "/^group = www-data/c\group = vagrant" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
    sed -i "/display_errors = Off/c\display_errors = On" /etc/php/$PHP_VERSION/fpm/php.ini
    sed -i "/display_errors = Off/c\display_errors = On" /etc/php/$PHP_VERSION/cli/php.ini

    service php${PHP_VERSION}-fpm restart

    # restart nginx
    service nginx reload

    echo "Install composer.."
    if [ ! -f /usr/local/bin/composer ]; then
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
    fi

    echo 'alias ll="ls -al"' > /home/vagrant/.bash_aliases
}


function resetJelixMysql() {
    local base="$1"
    local login="$2"
    local pass="$3"
    local prefix="$4"
    mysql -u $login -p$pass -e "drop table if exists ${prefix}jacl2_group;drop table if exists ${prefix}jacl2_rights;drop table if exists ${prefix}jacl2_subject;drop table if exists ${prefix}jacl2_subject_group;drop table if exists ${prefix}jlx_cache;drop table if exists ${prefix}jlx_user;drop table if exists ${prefix}jsessions;drop table if exists ${prefix}jacl2_user_group;" $base;
}

function resetJelixTemp() {
    local appdir="$1"
    if [ ! -d $appdir/temp/ ]; then
        mkdir $appdir/temp/
    else
        rm -rf $appdir/temp/*
    fi
    touch $appdir/temp/.dummy
}

function resetJelixInstall() {
    local appdir="$1"

    if [ -f $appdir/var/config/CLOSED ]; then
        rm -f $appdir/var/config/CLOSED
    fi

    if [ ! -d $appdir/var/log ]; then
        mkdir $appdir/var/log
    fi

    if [ -f $appdir/var/config/profiles.ini.php.dist ]; then
        cp -a $appdir/var/config/profiles.ini.php.dist $appdir/var/config/profiles.ini.php
    fi
    if [ -f $appdir/var/config/localconfig.ini.php.dist ]; then
        cp -a $appdir/var/config/localconfig.ini.php.dist $appdir/var/config/localconfig.ini.php
    fi
    if [ -f $appdir/var/config/installer.ini.php ]; then
        rm -f $appdir/var/config/installer.ini.php
    fi
    resetJelixTemp $appdir
}

function runComposer() {
    cd $1
    su -c "composer install" vagrant
}

function resetComposer() {
    cd $1
    if [ -f composer.lock ]; then
        rm -f composer.lock
    fi
    su -c "composer install" vagrant
}

function initapp() {
    php $1/install/configurator.php --no-interaction --verbose
    php $1/install/installer.php --verbose
}

