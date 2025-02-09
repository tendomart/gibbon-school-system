#!/bin/sh
set -e
environment='production'

# Check if the environment variable is set
if [ -z "$GIBBON_STUDENTS" ]; then
    students="30"
else
    students="$GIBBON_STUDENTS"
fi
# xdebug setup
if [ -n "$DEBUG" ]; then
    environment='development'
    echo "Debug mode enabled"
    # Install xdebug PECL extension
    pecl install xdebug
    CONTAINER_IP=`/sbin/ip route|awk '/default/ { print $3 }'`    
    cat << EOF > $PHP_INI_DIR/conf.d/debug.ini
zend_extension=xdebug.so
xdebug.cli_color = 1
xdebug.client_host=${CONTAINER_IP}
xdebug.log_level=0
xdebug.mode=develop,debug
xdebug.show_error_trace = On
xdebug.start_with_request=yes
xdebug.var_display_max_children = 128
xdebug.var_display_max_data = 128
xdebug.var_display_max_depth = 8
max_execution_time=600
EOF

else
    echo "Debug mode not enabled"
    rm -f $PHP_INI_DIR/conf.d/debug.ini
    cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
fi
#generate php.ini based on development/production php recommendations
if [ ! -e "$PHP_INI_DIR/php.ini" ]; then
    cp $PHP_INI_DIR/php.ini-$environment $PHP_INI_DIR/php.ini
    echo "\nmax_input_vars=5000\n" >> $PHP_INI_DIR/php.ini
    echo "max_file_uploads=$students\n" >> $PHP_INI_DIR/php.ini
fi

if [ -n "$MYSQL_HOST" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ] && [ -n "$MYSQL_DATABASE" ]; then
    if [ ! -e "config.php" ]; then
        guid="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
        if [ -n "$GUID" ]; then 
            guid="$GUID"
        fi        
        echo "File config.php does not exists, Configuring instance with environment variables"        	        
        twigc resources/templates/installer/config.twig.html -p "guid='$guid'" -p "databaseServer='$MYSQL_HOST'" -p "databaseUsername='$MYSQL_USER'"  -p "databasePassword='$MYSQL_PASSWORD'" -p "databaseName='$MYSQL_DATABASE'" | grep -v '^Deprecated:'> config.php        
        rm -Rf installer
        # Check if admin record exists
        if [[ $(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -N -B -e "SELECT COUNT(*) FROM gibbonPerson WHERE gibbonPersonID=1;") -eq 0 ]]; then
            # Generate a random password
            if [[ -z "${GIBBON_ADMIN_PASSWORD}" ]]; then
                PASSWORD=$(openssl rand -base64 12)
            else
                PASSWORD=${GIBBON_ADMIN_PASSWORD}
            fi

            # Set environment variables
            export EMAIL="${GIBBON_ADMIN_EMAIL:=admin@example.com}"
            export USERNAME="${GIBBON_ADMIN_USERNAME:=admin}"
            export PASSWORD_STRONG="$PASSWORD"
            export PASSWORD_STRONG_SALT="$(openssl rand -base64 12)"
            export STATUS="active"
            export CAN_LOGIN=1
            export PASSWORD_FORCE_RESET=0
            export GIBBON_ROLE_ID_PRIMARY=1
            export GIBBON_ROLE_ID_ALL=1

            # Insert new record
            mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" <<EOF
            INSERT INTO gibbonPerson (gibbonPersonID, title, surname, firstName, preferredName, officialName, username, passwordStrong, passwordStrongSalt, status, canLogin, passwordForceReset, gibbonRoleIDPrimary, gibbonRoleIDAll, email)
            VALUES (1, '', '', '', '', '', '\$USERNAME', '\$PASSWORD_STRONG', '\$PASSWORD_STRONG_SALT', '\$STATUS', \$CAN_LOGIN, \$PASSWORD_FORCE_RESET, \$GIBBON_ROLE_ID_PRIMARY, \$GIBBON_ROLE_ID_ALL, '\$EMAIL');
EOF
            if [[ -z "${GIBBON_ADMIN_PASSWORD}" ]]; then
                echo "New user inserted. Generated password: $PASSWORD"
            else
                echo "New user inserted.
            fi
        else
            echo "Record already exists."
        fi
    fi
    unset MYSQL_HOST MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE 
fi
# new volume could contain diferent permissions, asure permissions on uploads are ok
owner=$(stat -c "%U" "uploads")
if [ "$owner" != "33" ]; then
    chown -R 33:33 uploads
    chmod -R g+w uploads
    chmod -R u+w uploads
    chmod -R o-w uploads
fi
sh /usr/local/bin/docker-php-entrypoint "$@"