#!/bin/bash
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
TURQUOISE='\e[96m'
ENDCOLOR='\e[0m'

echo "Welcome to apache web server installer & manager!"

if [ "$(groups "$USER" | grep -c -E '\bsudo\b|\broot\b')" -eq 0 ] && [[ $EUID -ne 0 ]]; then
    echo "You don't have permissions to run this script. Please run as sudo."
    exit 1
fi

if [ "$(sudo apt-cache policy apache2 | grep "Installed:" | grep -c '\bnone\b')" -eq 0 ] && ! [ -f /etc/apache2/.installedWithAWI ]; then
    echo "Apache2 was installed without using this script."
    echo "This script will not work properly."
    echo "Exiting..."
    exit 0
fi

OS=$(grep '\bID=\b' /etc/os-release | cut -d= -f2)
OS_LIKE=$(grep '\bID_LIKE\b' /etc/os-release | cut -d= -f2 | tr -d '"' | grep -E -c 'debian|ubuntu')

if [[ "${OS}" != "pop" ]] || [ "${OS_LIKE}" -eq 0 ]; then
    echo -e "${YELLOW}This script wasn't tested on your operating system. (pop, debian, ubuntu)"
    echo -e "If your system is using ${RED}apt${YELLOW}, this script may work.${ENDCOLOR}"
    
    until [[ ${CONTINUE} =~ ^[YyNn]$ ]]; do
        read -p "Would you like to continue? [y/N]: " -r -n 1 CONTINUE
        echo ""
    done
    if [[ ${CONTINUE} =~ ^[Nn]$ ]]; then
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
    
    initMessage "Creating system administrator"
    sudo useradd -c "Administrator" -m -s /bin/bash admin
    echo "Please enter password for admin user"
    sudo passwd admin
    outputParser $? "System administrator created successfully." "An error occured while creating system administrator. Reffer to error."
    
    initMessage "Setting webadmin's permissions"
    sudo usermod -a -G sudo admin
    sudo touch /var/www/.users
    
    outputParser $? "Permissions set successfully." "An error occured while setting permissions. Reffer to error."
    sudo rm -rf /var/www/html/index.html 
    sudo cp ./lib/index_default.php /var/www/html/index.php
    sudo /bin/sh -c "mysql -e \"CREATE DATABASE admin\""
    sudo /bin/sh -c "mysql -e \"GRANT ALL PRIVILEGES ON admin.* TO 'admin'@'localhost' IDENTIFIED BY 'admin';\""
    sudo /bin/sh -c "mysql -e \"FLUSH PRIVILEGES;\""
    initMessage "Default website can be found at http://localhost"

    menu
}


function createDomainForUser {
    initMessage "Creating user website"

    if [ $# -eq 0 ]; then
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

        pickedUserNumber=false
        pickedUser=0
        until $pickedUserNumber; do
            read -p "Select user [1-$counter]: " -r pickedUser
            if [[ $pickedUser =~ ^[1-9][0-9]*$ ]] && [ "$pickedUser" -le "$counter" ] && [ "$pickedUser" -gt 0 ]; then
                pickedUserNumber=true
            fi
            echo ""
        done

        user=${availableUsers[$pickedUser]}
    else
        user=$1
    fi
    echo -e "User ${TURQUOISE}$user${ENDCOLOR} selected."
    echo ""
    echo "Enter the domain name without .tld"
    until [[ ${domainName} =~ ^[a-z]+$ ]]; do
        read -p "Enter domain name [google]: " -r domainName
        echo ""
    done

    domain="$domainName.$user.localhost"
    domainCheck=$(sudo ls /var/www/"$user" | grep -c "$domain")
    if [ "${domainCheck}" -eq 1 ]; then
        echo "Domain already exists!"
        exit 1
    fi

    sudo cp ./lib/domain.conf /etc/apache2/sites-available/"$domain".conf
    
    sudo sed -i "s/%domain_name%/$domain/g" /etc/apache2/sites-available/"$domain".conf
    sudo sed -i "s/%user%/$user/g" /etc/apache2/sites-available/"$domain".conf
    sudo a2ensite "$domain".conf
    sudo systemctl reload apache2
    outputParser $? "Domain created successfully." "An error occured while creating domain. Reffer to error."
    initMessage "Test website is located at http://$domain and it's folder is in /var/www/$user/$domain"

    db_password=$user"_heslo"
    db_name="$user"_"$domainName"
    sudo mkdir /var/www/"$user"/"$domain"
    sudo cp ./lib/index.php /var/www/"$user"/"$domain"/
    sudo sed -i "s/%user%/$user/g" /var/www/"$user"/"$domain"/index.php
    sudo sed -i "s/%password%/$db_password/g" /var/www/"$user"/"$domain"/index.php
    sudo sed -i "s/%databaseName%/$db_name/g" /var/www/"$user"/"$domain"/index.php
    sudo chown -R "$user":www-data /var/www/"$user"

    sudo /bin/sh -c "mysql -e \"CREATE DATABASE $db_name\""
    sudo /bin/sh -c "mysql -e \"GRANT ALL PRIVILEGES ON $db_name.* TO '$user'@'localhost' IDENTIFIED BY '$db_password';\""
    sudo /bin/sh -c "mysql -e \"FLUSH PRIVILEGES;\""
    exit 0
}

function addUser {
    initMessage "Adding new user"
    username=""
    until [[ ${username} =~ ^[a-z0-9]+$ ]]; do
        read -p "Enter username [lowercase]: " -r username
    done

    if [ "$(grep -c -e "^$username:" /etc/passwd)" -ne 0 ]; then
        echo -e "Uzivatel ${RED}$username${ENDCOLOR} uz existuje."
        exit 1
    fi
    echo ""
    
    sudo mkdir /var/www/"${username}"/
    sudo useradd -d /var/www/"${username}" -s /bin/bash "${username}"
    sudo chown -R "${username}":www-data /var/www/"${username}"
    sudo chmod -R 750 /var/www/"${username}"
    
    echo "Please enter password for ${username}"
    sudo passwd "${username}"
    outputParser $? "User created successfully." "An error occured while creating user. Reffer to error."
    echo "$username" | sudo tee -a /var/www/.users > /dev/null
    
    createDomainForUser "$username"
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

    pickedUserNumber=false
    pickedUser=0
    until $pickedUserNumber; do
        read -p "Select user [1-$counter]: " -r pickedUser
        if [[ $pickedUser =~ ^[1-9][0-9]*$ ]] && [ "$pickedUser" -le "$counter" ] && [ "$pickedUser" -gt 0 ]; then
            pickedUserNumber=true
        fi
        echo ""
    done

    user=${availableUsers[$pickedUser]}
    echo ""
    echo -e "User ${TURQUOISE}$user${ENDCOLOR} selected."
    echo ""
    sudo userdel -r "$user"
    outputParser $? "User removed successfully." "An error occured while removing user. Reffer to error."
    sudo sed -i "/^$user$/d" /var/www/.users
    sudo rm -rf /var/www/"$user"
    sudo a2dissite *."$user".localhost.conf
    sudo systemctl reload apache2
    outputParser $? "User domains disabled successfully." "An error occured while disabling user domains. Reffer to error."
    menu
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
    sudo apt purge apache2 php* mariadb-server -y
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
