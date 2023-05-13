#!/bin/bash
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
TURQUOISE='\e[96m'
ENDCOLOR='\e[0m'

#COMPLETED:
# - Inštalácia apache2
# - Inštalácia MariaDB
# - Inštalácia PHP a modulov
# - Zabezpečenie MariaDB
# - Vytvorenie webadmina a nastavenie práv
# - Vytvorenie domény pre používateľa

#TODO:
# - Vytvorenie databázy pre používateľa


echo "Welcome to apache web server installer & manager!"
#Overenie ci je pouzivatel v sudo skupine
if [ "$(groups "$USER" | grep -c -E '\bsudo\b|\broot\b')" -eq 0 ]; then
    echo "You don't have permissions to run this script. Please run as sudo."
    exit 1
fi

#Overenie ci je apache2 nainstalovany tymto skriptom pre spravne fungovanie configov
if [ "$(sudo apt-cache policy apache2 | grep "Installed:" | grep -c '\bnone\b')" -eq 0 ] && ! [ -f /etc/apache2/.installedWithAWI ]; then
    echo "Apache2 was installed without using this script."
    echo "This script will not work properly."
    echo "Exiting..."
    exit 0
fi

#Overenie operacneho systemu
OS=$(grep '\bID=\b' /etc/os-release | cut -d= -f2)
OS_LIKE=$(grep '\bID_LIKE\b' /etc/os-release | cut -d= -f2 | tr -d '"' | grep -E -c 'debian|ubuntu')

if [[ "${OS}" != "pop" ]] || [ "${OS_LIKE}" -eq 0 ]; then
    echo -e "${YELLOW}This script wasn't tested on your operating system. (pop, debian, ubuntu)"
    echo -e "If your system is using ${RED}apt${YELLOW}, this script may work.${ENDCOLOR}"
    
    until [[ ${CONTINUE} =~ ^[YyNn]$ ]]; do
        read -p "Would you like to continue? [y/N]: " -r -n 1 CONTINUE
        echo ""
    done
    if [[ ! ${CONTINUE} =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi


# $1 - message
function initMessage {
    echo ""
    echo -e "${YELLOW} - $1${ENDCOLOR}"
}

# $1 - exit code
# $2 - success message
# $3 - error message
function outputParser {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN} - $2${ENDCOLOR}"
    else
        echo -e "${RED} - $3${ENDCOLOR}"
        exit 1
    fi
}

function initialInstall {
    initMessage "Updating system"
    sudo apt update -y && sudo apt upgrade -y
    outputParser $? "System succesfully updated." "An error occured while updating. Reffer to error."
    
    initMessage "Installing web server (Apache2)"
    sudo apt install apache2 -y
    outputParser $? "Apache installed successfully." "An error occured while installing apache. Reffer to error."
    sudo touch /etc/apache2/.installedWithAWI
    sudo chmod 444 /etc/apache2/.installedWithAWI
    
    initMessage "Installing database server (MariaDB)"
    sudo apt install mariadb-server -y
    outputParser $? "MariaDB installed successfully." "An error occured while installing MariaDB. Reffer to error."
    
    initMessage "Securing MariaDB. Please follow the instructions below."
    echo "Example answers can be found here: https://haste.mazurky.eu/raw/mysql_secure_installation"
    echo "Press any key to continue..."
    read -r -n 1
    sudo mysql_secure_installation
    outputParser $? "MariaDB secured successfully." "An error occured while securing MariaDB. Reffer to error."
    
    initMessage "Installing php and recomended modules"
    sudo apt install php libapache2-mod-php php-mysql php-common php-zip php-gd php-mbstring php-curl php-xml -y
    outputParser $? "PHP installed successfully." "An error occured while installing PHP and it's modules. Reffer to error."
    
    initMessage "Restarting apache2"
    sudo systemctl restart apache2
    outputParser $? "Apache restarted successfully." "An error occured while restarting apache. Reffer to error."
    
    initMessage "Enabling apache2 to start on boot"
    sudo systemctl enable apache2
    outputParser $? "Apache enabled successfully." "An error occured while enabling apache. Reffer to error."
    
    initMessage "Enabling MariaDB to start on boot"
    sudo systemctl enable mariadb
    outputParser $? "MariaDB enabled successfully." "An error occured while enabling MariaDB. Reffer to error."
    
    initMessage "Web administrator setup"
    sudo useradd -c "Webovy Administrator" -d /var/www -s /bin/bash webadmin
    echo "Please enter password for webadmin user"
    sudo passwd webadmin
    outputParser $? "Webadmin user created successfully." "An error occured while creating webadmin user. Reffer to error."
    
    initMessage "Setting webadmin's permissions"
    sudo usermod -a -G sudo webadmin
    sudo chmod -R 770 /var/www
    sudo chown -R www-data:www-data /var/www
    sudo touch /var/www/.users
    
    outputParser $? "Permissions set successfully." "An error occured while setting permissions. Reffer to error."
    sudo rm -rf /var/www/html/index.html 
    sudo cp ./lib/index_default.php /var/www/html/index.php
    initMessage "Default website can be found at http://localhost"
    echo "Default website and database will be deleted after first user is added."

    # Keďže root nemá heslo na mariadb, tak nemôžem isť cez mysql -uroot a -p....
    sudo /bin/sh -c "mysql -e \"CREATE DATABASE webadmin\""
    sudo /bin/sh -c "mysql -e \"GRANT ALL PRIVILEGES ON webadmin.* TO 'webadmin'@'localhost' IDENTIFIED BY 'webadmin';\""
    sudo /bin/sh -c "mysql -e \"FLUSH PRIVILEGES;\""
    menu
}


function createDomainForUser {
    initMessage "Creating user website"
    echo "Select user from users!"
    echo ""
    echo "Users:"
    counter=1
    declare -A availableUsers
    while IFS= read -r line; do
        availableUsers[$counter]=$line
        echo "   $counter) $line"
        counter=$((counter+1))
    done <<< "$(sudo cat /var/www/.users)"

    counter=$((counter-1))

    
    until [[ ${pickedUser} =~ ^[1-$counter]$ ]]; do
        read -p "Select user [1-$counter]: " -r -n 1 pickedUser
        echo ""
    done

    user=${availableUsers[$pickedUser]}
    echo ""
    echo -e "User ${TURQUOISE}$user${ENDCOLOR} selected."
    echo ""
    echo "Enter the domain name without .tld"
    until [[ ${domainName} =~ ^[a-z]+$ ]]; do
        read -p "Enter domain name [google]: " -r domainName
        echo ""
    done
    
    domain="$domainName.$user.localhost"
    sudo cp ./lib/domain.conf /etc/apache2/sites-available/"$domain".conf
    
    sudo sed -i "s/%domain_name%/$domain/g" /etc/apache2/sites-available/"$domain".conf
    sudo sed -i "s/%user%/$user/g" /etc/apache2/sites-available/"$domain".conf
    sudo a2ensite "$domain".conf
    sudo systemctl reload apache2
    outputParser $? "Domain created successfully." "An error occured while creating domain. Reffer to error."
    initMessage "Test website is located at http://$domain and it's folder is in /var/www/$user/$domain"

    db_password=$(openssl rand -base64 8)
    sudo mkdir /var/www/"$user"/"$domain"
    sudo cp ./lib/index.php /var/www/"$user"/"$domain"/
    chown -R "$user":www-data /var/www/"$user"
    sudo sed -i "s/%user%/$user/g" /var/www/"$user"/"$domain"/index.php
    sudo sed -i "s/%password%/$db_password/g" /var/www/"$user"/"$domain"/index.php
    sudo sed -i "s/%databaseName%/$domainName/g" /var/www/"$user"/"$domain"/index.php

    sudo /bin/sh -c "mysql -e \"CREATE DATABASE $domainName\""
    sudo /bin/sh -c "mysql -e \"GRANT ALL PRIVILEGES ON $user.* TO '$user'@'localhost' IDENTIFIED BY '$db_password';\""
    sudo /bin/sh -c "mysql -e \"FLUSH PRIVILEGES;\""
}

function addUser {
    initMessage "Adding new user"
    until [[ ${username} =~ ^[a-z0-9]+$ ]]; do
        read -p "Enter username [lowercase]: " -r username
    done
    echo ""
    until [[ ${nameSurname} =~ ^[a-zA-Z]+$ ]]; do
        read -p "Enter your name and surname: " -r nameSurname
    done
    echo ""
    
    sudo mkdir /var/www/"${username}"/
    sudo useradd -c "${nameSurname}" -d /var/www/"${username}" -s /bin/bash "${username}"
    sudo chown -R "${username}":www-data /var/www/"${username}"
    sudo chmod -R 750 /var/www/"${username}"
    
    echo "Please enter password for ${username}"
    sudo passwd "${username}"
    outputParser $? "User created successfully." "An error occured while creating user. Reffer to error."
    echo "$username" | sudo tee -a /var/www/.users
    
    createDomainForUser    
    
}

function removeUser {
    initMessage "Remove user"
    echo "Select user from users!"
    echo ""
    echo "Users:"
    counter=1
    declare -A availableUsers
    while IFS= read -r line; do
        availableUsers[$counter]=$line
        echo "   $counter) $line"
        counter=$((counter+1))
    done <<< "$(sudo cat /var/www/.users)"

    counter=$((counter-1))

    until [[ ${pickedUser} =~ ^[1-$counter]$ ]]; do
        read -p "Select user [1-$counter]: " -r -n 1 pickedUser
        echo ""
    done

    user=${availableUsers[$pickedUser]}
    echo ""
    echo -e "User ${TURQUOISE}$user${ENDCOLOR} selected."
    echo ""
}

function listUsers {
    echo "Available users:"
    while IFS= read -r line; do
        echo -e "   ${YELLOW}$line${ENDCOLOR}"
    done <<< "$(sudo cat /var/www/.users)"

    CONTINUE=""
    until [[ ${CONTINUE} =~ ^[YyNn]$ ]]; do
        read -p "Exit? [y/N]: " -r -n 1 CONTINUE
        echo ""
    done
    if [[ ${CONTINUE} =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi

    menu
}

function uninstall {
    echo -e "${YELLOW} - Uninstalling web server (apache2, php and mariaDB)${ENDCOLOR}"
    sudo rm -rf /etc/apache2/.installedWithAWI
    sudo apt purge apache2 php php* mariadb-server -y
    sudo apt autoremove -y
    outputParser $? "Web server uninstalled successfully." "An error occured while uninstalling web server. Reffer to error."
}

function menu() {
    PICKED_OPTION=""
    if [ -f /etc/apache2/.installedWithAWI ]; then
        #if true; then
        echo ""
        echo "Options:"
        echo "   1) Add new user"
        echo "   2) Create domain for user"
        echo "   3) Remove existing user"
        echo "   4) List all users"
        echo "   5) Uninstall web server (apache2, php and mariaDB)"
        echo "   6) Exit"
        
        until [[ ${PICKED_OPTION} =~ ^[1-6]$ ]]; do
            read -p "Select option [1-6]: " -r -n 1 PICKED_OPTION
            echo ""
        done
        case "${PICKED_OPTION}" in
            1)
                addUser
            ;;
            2)
                createDomainForUser
            ;;
            3)
                removeUser
            ;;
            4)
                listUsers
            ;;
            5)
                uninstall
            ;;
            6)
                echo "Exiting..."
                exit 0
            ;;
        esac
    else
        echo ""
        echo "Options:"
        echo "   1) Install web server (apache2, php and mariaDB)"
        echo "   2) Exit"
        
        until [[ ${PICKED_OPTION} =~ ^[1-2]$ ]]; do
            read -p "Select option [1-2]: " -r -n 1 PICKED_OPTION
            echo ""
        done
        case "${PICKED_OPTION}" in
            1)
                initialInstall
            ;;
            2)
                echo "Exiting..."
                exit 0
            ;;
        esac
    fi
}
menu