#!/bin/bash

############## >> Функция удаления юзера с сайтом. Используется, если что-то пойдёт не так

function site_remove {
    echo "ERROR: Delete everything that was added."
    echo "$SCRIPTPATH/remove.sh $ROOTPASS $USERNAME"

    $SCRIPTPATH/remove.sh $ROOTPASS $USERNAME
}

##############

MAXLENGTH=16
TIMEZONE='Europe/Moscow'
MYSQLPASS=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12`
SFTPPASS=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12`
PASSWORD=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12`
CONFIGKEY=`< /dev/urandom tr -dc _a-z-0-9 | head -c4`
DOMAIN=''
VERSION=''

############## >> Обработка переданных параметров

NO_ARGS=0

if [ $# -eq "$NO_ARGS" ]
then
    echo "ERROR: Incorrect usage"
    exit 0
fi


while getopts "p:h:u:d:v:c:m:t:" Option
do
    case $Option in
        p) ROOTPASS=$OPTARG;;
        h) HOST=$OPTARG;;
        u) USERNAME=$OPTARG;;
        d) DOMAIN=$OPTARG;;
        v) VERSION=$OPTARG;;
        c) CONNECTORSNAME=$OPTARG;;
        m) MANAGERNAME=$OPTARG;;
        t) TABLEPREFIX=$OPTARG;;
        *) echo "ERROR: Invalid key";;
    esac
done
shift $(($OPTIND - 1))

############## <<

##############

if [ -z "$SCRIPTPATH" ]; then
    SCRIPTPATH=`dirname $0`
fi

############## MySQL root password

echo -e "$ROOTPASS" | grep "*"
if [ "$?" -ne 1 -o -z "$ROOTPASS" ]; then
    echo "ERROR: Enter MySQL root password"
    exit 0
fi

##############

echo -e "$HOST" | grep "[^A-Za-z0-9.\-]"
if [ "$?" -ne 1 -o -z "$HOST" ]; then
    echo "ERROR: Host domain bad symbols"
    exit 0
fi

##############

echo -e "$USERNAME" | grep "[^A-Za-z0-9]"
if [ "$?" -ne 1 -o -z "$USERNAME" ]; then
    echo "ERROR: Username bad symbols"
    exit 0
fi
if [ "${#USERNAME}" -gt "$MAXLENGTH" ]; then
    echo "ERROR: Username length more $MAXLENGTH"
    exit 0
fi

##############

if [ -z "$DOMAIN" ]; then
    DOMAIN=""
else
    echo -e "$DOMAIN" | grep "[^A-Za-z0-9.\-]"
    if [ "$?" -ne 1 ]; then
        echo "ERROR: Domain bad symbols"
        exit 0
    fi
    DOMAIN=`echo "$DOMAIN" | sed 's/\(^www.\)\(.*\)/\2/'` # вырезаем www.
fi

if [ -z "$DOMAIN" ]; then
    DOMAIN="$USERNAME.$HOST"
fi

############## Enter pl version MODX Revo (example: "2.5.0-pl")

if [ -z "$VERSION" ]; then
    VERSION=""
else
    echo -e "$VERSION" | grep "[^A-Za-z0-9.\-]"
    if [ "$?" -ne 1 ]; then
        echo "ERROR: Version bad symbols"
        exit 0
    fi
fi

############## Connectors dir name

if [ -z "$CONNECTORSNAME" ]; then
    CONNECTORSNAME=""
else
    echo -e "$CONNECTORSNAME" | grep "[^_a-z0-9\-]"
    if [ "$?" -ne 1 ]; then
        echo "ERROR: Connectors dir name is bad symbols"
        exit 0
    fi
fi

if [ -z "$CONNECTORSNAME" ]; then
    CONNECTORSNAME="connectors"
fi

############## Manager dir name

if [ -z "$MANAGERNAME" ]; then
    MANAGERNAME=""
else
    echo -e "$MANAGERNAME" | grep "[^a-z0-9_\-]"
    if [ "$?" -ne 1 ]; then
        echo "ERROR: Manager dir name is bad symbols"
        exit 0
    fi
fi

if [ -z "$MANAGERNAME" ]; then
    MANAGERNAME="manager"
fi

############## Tables prefix

if [ -z "$TABLEPREFIX" ]; then
    TABLEPREFIX=""
else
    echo -e "$TABLEPREFIX" | grep "[^_a-z0-9\-]"
    if [ "$?" -ne 1 ]; then
        echo "ERROR: Tables prefix is bad symbols"
        exit 0
    fi
fi

if [ -z "$TABLEPREFIX" ]; then
    TABLEPREFIX="modx_${USERNAME}_"
fi

##############

echo "Creating user and home directory..."

useradd $USERNAME -m -G sftp -s "/bin/false" -d "/var/www/$USERNAME"
if [ "$?" -ne 0 ]; then
    echo "ERROR: Can't add user"
    exit 0
fi
echo $SFTPPASS > /var/www/$USERNAME/tmp
echo $SFTPPASS >> /var/www/$USERNAME/tmp
cat /var/www/$USERNAME/tmp | passwd $USERNAME
rm /var/www/$USERNAME/tmp

##############

mkdir /var/www/$USERNAME/www
mkdir /var/www/$USERNAME/tmp
chmod -R 755 /var/www/$USERNAME/
chown -R $USERNAME:$USERNAME /var/www/$USERNAME/
chown root:root /var/www/$USERNAME

echo "Creating vhost files"

echo "upstream backend-$USERNAME {server unix:/var/run/php7.0-$USERNAME.sock;}

#server {
#    #server_name pma.$USERNAME.$HOST;
#    #root /var/www/pma/www;
#    #location / {
#    #    proxy_pass http://pma.$HOST/;
#    #}
#
#    # Remove double slashes in url
#    location ~* .*//+.* {
#        rewrite (.*)//+(.*) \$1/\$2 permanent;
#    }
#}
server {
    server_name www.$USERNAME.$HOST;
    return 301 \$scheme://$USERNAME.$HOST\$request_uri;
}
server {
    server_name $USERNAME.$HOST;

    # Include site config
    include /etc/nginx/conf.inc/main/$USERNAME.conf;
    include /etc/nginx/conf.inc/access/$USERNAME.conf;
}
include /etc/nginx/conf.inc/domains/$USERNAME.conf;" > /etc/nginx/sites-available/$USERNAME.conf
ln -s /etc/nginx/sites-available/$USERNAME.conf /etc/nginx/sites-enabled/$USERNAME.conf

echo "listen 80;
charset utf-8;
root /var/www/$USERNAME/www;
access_log /var/log/nginx/$USERNAME-access.log;
error_log /var/log/nginx/$USERNAME-error.log;
index index.php index.html;
rewrite_log on;

location ~* ^/($MANAGERNAME|$CONNECTORSNAME|_build)/ {
    location ~ \.php$ {
        try_files \$uri =404;

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass backend-$USERNAME;
    }
    break;
}

# Remove double slashes in url
location ~* .*//+.* {
    rewrite (.*)//+(.*) \$1/\$2 permanent;
}

# PHP handler
location ~ \.php$ {
    try_files \$uri =404;

    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_pass backend-$USERNAME;
}" > /var/www/$USERNAME/main.nginx
ln -s /var/www/$USERNAME/main.nginx /etc/nginx/conf.inc/main/$USERNAME.conf

echo "# Hide modx /core/ directory
location ~* ^/core/ {
    return 404;
}

# If file and folder not exists -->
location / {
    try_files \$uri \$uri/ @rewrite;
}
# --> then redirect request to entry modx index.php
location @rewrite {
    rewrite ^/((ru|en|kz)/assets/(.*))$ /assets/\$3 last;
    rewrite ^/((ru|en|kz)/(.*)/?)$ /index.php?q=\$1 last;
    rewrite (.*)/$ \$scheme://\$host\$1 permanent;
    rewrite ^/(.*)$ /index.php?q=\$1 last;
}" > /var/www/$USERNAME/access.nginx
ln -s /var/www/$USERNAME/access.nginx /etc/nginx/conf.inc/access/$USERNAME.conf

if [ -z "$DOMAIN" ]; then
    echo "" > /var/www/$USERNAME/domains.nginx
else
    echo "server {
    server_name www.$DOMAIN;
    return 301 \$scheme://$DOMAIN\$request_uri;
}
server {
    server_name $DOMAIN;

    # Include site config
    include /etc/nginx/conf.inc/main/$USERNAME.conf;
    include /etc/nginx/conf.inc/access/$USERNAME.conf;
}" > /var/www/$USERNAME/domains.nginx
fi
ln -s /var/www/$USERNAME/domains.nginx /etc/nginx/conf.inc/domains/$USERNAME.conf

##############

#echo "Creating php7.0-fpm config"

echo "[$USERNAME]

listen = /var/run/php7.0-$USERNAME.sock
listen.mode = 0666
user = $USERNAME
group = $USERNAME
chdir = /var/www/$USERNAME

php_admin_value[upload_tmp_dir] = /var/www/$USERNAME/tmp
php_admin_value[soap.wsdl_cache_dir] = /var/www/$USERNAME/tmp
php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[open_basedir] = /var/www/$USERNAME/
php_admin_value[cgi.fix_pathinfo] = 0
php_admin_value[date.timezone] = $TIMEZONE
php_admin_value[session.gc_probability] = 1
php_admin_value[session.gc_divisor] = 100

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 4" > /etc/php/7.0/fpm/pool.d/$USERNAME.conf

##############

#echo "Restarting php7.0-fpm"
#service php7.0-fpm stop && service php7.0-fpm start

##############

#echo "Creating config.xml"

echo "<modx>
    <database_type>mysql</database_type>
    <database_server>localhost</database_server>
    <database>$USERNAME</database>
    <database_user>$USERNAME</database_user>
    <database_password>$MYSQLPASS</database_password>
    <database_connection_charset>utf8</database_connection_charset>
    <database_charset>utf8</database_charset>
    <database_collation>utf8_unicode_ci</database_collation>
    <table_prefix>$TABLEPREFIX</table_prefix>
    <https_port>443</https_port>
    <http_host>$USERNAME.$HOST</http_host>
    <cache_disabled>0</cache_disabled>

    <inplace>1</inplace>

    <unpacked>0</unpacked>

    <language>ru</language>

    <cmsadmin>$USERNAME</cmsadmin>
    <cmspassword>$PASSWORD</cmspassword>
    <cmsadminemail>admin@$USERNAME.$HOST</cmsadminemail>

    <core_path>/var/www/$USERNAME/www/core/</core_path>

    <context_mgr_path>/var/www/$USERNAME/www/$MANAGERNAME/</context_mgr_path>
    <context_mgr_url>/$MANAGERNAME/</context_mgr_url>
    <context_connectors_path>/var/www/$USERNAME/www/$CONNECTORSNAME/</context_connectors_path>
    <context_connectors_url>/$CONNECTORSNAME/</context_connectors_url>
    <context_web_path>/var/www/$USERNAME/www/</context_web_path>
    <context_web_url>/</context_web_url>

    <remove_setup_directory>1</remove_setup_directory>
</modx>" > /var/www/$USERNAME/config.xml

#############

echo "Reloading nginx"
service nginx reload

echo "Restarting php7.0-fpm"
service php7.0-fpm restart

##############

echo "Creating database"

Q1="CREATE DATABASE IF NOT EXISTS $USERNAME DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
Q2="GRANT ALTER,DELETE,DROP,CREATE,INDEX,INSERT,SELECT,UPDATE,CREATE TEMPORARY TABLES,LOCK TABLES ON $USERNAME.* TO '$USERNAME'@'localhost' IDENTIFIED BY '$MYSQLPASS';"
Q3="FLUSH PRIVILEGES;"
SQL="${Q1}${Q2}${Q3}"

mysql -uroot --password=$ROOTPASS -e "$SQL"

##############

echo "Installing MODX Revo"

cd /var/www/$USERNAME/www/

echo "Getting file from modx.com..."
if [ -z "$VERSION" ]; then
    sudo -u $USERNAME wget -O modx.zip http://modx.com/download/latest/
else
    sudo -u $USERNAME wget -O modx.zip http://modx.com/download/direct/modx-$VERSION.zip
fi

# Имитируем неудачную загрузку modx.zip
#touch modx.zip

############## Проверка скачанного архива на нулевой размер

ZIPSIZE=`ls -l ./modx.zip | cut -f 5 -d " "`
if [ "${ZIPSIZE}" = "0" ]; then
    echo "ERROR: Zip file is zero." && site_remove
    exit 0
fi

##############

echo "Unzipping file..."
sudo -u $USERNAME unzip "./modx.zip" -d ./ > /dev/null

##############

ZDIR=`ls -F | grep "\/" | head -1`
if [ "${ZDIR}" = "/" ]; then
    echo "ERROR: Failed to find directory." && site_remove
    exit 0
fi

if [ -d "${ZDIR}" ]; then
    cd ${ZDIR}
    echo "Moving out of temp dir..."
    sudo -u $USERNAME mv ./* ../
    cd ../
    #mv ./core/ ../core/
    sudo -u $USERNAME mv ./manager/ ./$MANAGERNAME/
    sudo -u $USERNAME mv ./connectors/ ./$CONNECTORSNAME/
    rm -r "./${ZDIR}"

    echo "Removing zip file..."
    rm "./modx.zip"

    cd "setup"
    echo "Running setup..."
    sudo -u $USERNAME php ./index.php --core_path=/var/www/$USERNAME/www/core/  --installmode=new --config=/var/www/$USERNAME/config.xml

    echo "Done!"
else
    echo "ERROR: Failed to find directory: ${ZDIR}" && site_remove
    exit 0
fi

echo "#!/bin/bash

echo \"Set permissions for /var/www/$USERNAME/www...\";
echo \"CHOWN files...\";
chown -R $USERNAME:$USERNAME \"/var/www/$USERNAME/www\";
echo \"CHMOD directories...\";
find \"/var/www/$USERNAME/www\" -type d -exec chmod 0755 '{}' \;
echo \"CHMOD files...\";
find \"/var/www/$USERNAME/www\" -type f -exec chmod 0644 '{}' \;
" > /var/www/$USERNAME/chmod
chmod +x /var/www/$USERNAME/chmod

echo "Manager:
http://$DOMAIN/$MANAGERNAME/
User: $USERNAME
Pass: $PASSWORD

SFTP:
User: $USERNAME
Pass: $SFTPPASS

MySQL:
User: $USERNAME
Pass: $MYSQLPASS" > /var/www/$USERNAME/pass.txt

#cat /var/www/$USERNAME/pass.txt

######### >> Выводим инфу для обработки в даймоне
echo "## INFO >>"

echo "##SITE##$DOMAIN##SITE_END##"

echo "##SFTP_PORT##22##SFTP_PORT_END##"
echo "##SFTP_USER##$USERNAME##SFTP_USER_END##"
echo "##SFTP_PASS##$SFTPPASS##SFTP_PASS_END##"

echo "##MYSQL_SITE##pma.$HOST##MYSQL_SITE_END##"
echo "##MYSQL_TABLE_PREFIX##$TABLEPREFIX##MYSQL_TABLE_PREFIX_END##"
echo "##MYSQL_DB##$USERNAME##MYSQL_DB_END##"
echo "##MYSQL_USER##$USERNAME##MYSQL_USER_END##"
echo "##MYSQL_PASS##$MYSQLPASS##MYSQL_PASS_END##"

echo "##MANAGER_SITE##/$MANAGERNAME/##MANAGER_SITE_END##"
echo "##MANAGER_USER##$USERNAME##MANAGER_USER_END##"
echo "##MANAGER_PASS##$PASSWORD##MANAGER_PASS_END##"

echo "##PATH##/var/www/$USERNAME/www/##PATH_END##"

echo "## << INFO"
######### << Выводим инфу для обработки в даймоне