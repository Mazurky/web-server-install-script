#!/bin/bash
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
ENDECHO='\e[0m'
#Overenie ci je pouzivatel v sudo skupine
if [ "$(groups "$USER" | grep -c -E '\bsudo\b|\broot\b')" -eq 0 ]; then
    echo "You don't have permissions to run this script. Please run as sudo."
    exit 1
fi

#Overenie ci je apache2 nainstalovany tymto skriptom pre spravne fungovanie configov
if [ "$(sudo apt-cache policy apache2 | grep "Installed:" | grep -c '\bnone\b')" -eq 0 ] && ! [ -f /etc/apache2/.installedWithAWI ]; then
    echo "Apache2 was installed without using this script."
    echo "This script will not work properly."
    exit 0
fi

#Overenie operacneho systemu
OS=$(grep '\bID=\b' /etc/os-release | cut -d= -f2)
OS_LIKE=$(grep '\bID_LIKE\b' /etc/os-release | cut -d= -f2 | tr -d '"' | grep -E -c 'debian|ubuntu')

if [[ "${OS}" != "pop" ]] || [ "${OS_LIKE}" -eq 0 ]; then
    echo -e "${YELLOW}Your operating system may not work properly with this script."
    echo -e "However, if your system is using ${RED}apt${YELLOW}, this script may work.${ENDECHO}"
    until [[ ${CONTINUE} =~ ^[YyNn]$ ]]; do
        read -p "Would you like to continue? [y/N]: " -n 1 -r CONTINUE
        echo ""
    done
    if [[ ! ${CONTINUE} =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi

# $1 - exit kód
# $2 - success message
# $3 - eror sprava
function outputParser {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN} - $2${ENDECHO}"
    else
        echo -e "${RED} - $3${ENDECHO}"
        exit 1
    fi
}

# $1 - sprava
function initMessage {
    echo ""
    echo -e "${YELLOW} - $1${ENDECHO}"
}

function configFile {
    sudo touch /etc/apache2/sites-available/awiconfig.conf
    sudo chmod 644 /etc/apache2/sites-available/awiconfig.conf
    sudo echo "<VirtualHost *:80>" >> /etc/apache2/sites-available/awiconfig.conf
    sudo echo "    ServerAdmin webmaster@localhost" >> /etc/apache2/sites-available/awiconfig.conf
    sudo echo "    DocumentRoot /var/www/awiconfig" >> /etc/apache2/sites-available/awiconfig.conf
    sudo echo "    ErrorLog ${APACHE_LOG_DIR}/error.log" >> /etc/apache2/sites-available/awiconfig.conf
    sudo echo "    CustomLog ${APACHE_LOG_DIR}/access.log combined" >> /etc/apache2/sites-available/awiconfig.conf
    sudo echo "</VirtualHost>" >> /etc/apache2/sites-available/awiconfig.conf
    sudo a2ensite awiconfig.conf
    sudo systemctl reload apache2
}

function initialInstall {
    initMessage "Updating system"
    sudo apt update -y && sudo apt upgrade -y
    outputParser $? "System succesfully updated." "An error occured while updating. Reffer to error."
    
    # Error example: https://img.mazurky.eu/2023/05/06/14-24-44_f67ef.png
    # Platí to aj pre ostatné inštalácie
    
    initMessage "Installing web server (Apache2)"
    sudo apt install apache2 -y
    outputParser $? "Apache installed successfully." "An error occured while installing apache. Reffer to error."
    sudo touch /etc/apache2/.installedWithAWI
    sudo chmod 444 /etc/apache2/.installedWithAWI
    
    initMessage "Installing database server (MariaDB)"
    sudo apt install mariadb-server -y
    outputParser $? "MariaDB installed successfully." "An error occured while installing MariaDB. Reffer to error."
    
    initMessage "Securing MariaDB"
    initMessage "Please follow the instructions below."
    echo "Example answers can be found here: https://haste.mazurky.eu/raw/mysql_secure_installation"
    read -rp "Press enter to continue..."
    sudo mysql_secure_installation
    
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
    initMessage "Please enter password for webadmin user"
    sudo passwd webadmin
    outputParser $? "Webadmin user created successfully." "An error occured while creating webadmin user. Reffer to error."
    
    initMessage "Setting webadmin user permissions"
    sudo usermod -a -G www-data webadmin && sudo chown -R webadmin:www-data /var/www && sudo chmod -R 770 /var/www
    outputParser $? "Permissions set successfully." "An error occured while setting permissions. Reffer to error."
    
    initMessage "Creating apache configuration"
    
}

function addUser {
    echo "Adding new user"
    #sudo chown jozko:www-data /var/www/jozko
    #sudo chmod 750 /var/www/jozko
    
}

function removeUser {
    echo "Removing existing user"
}

function listUsers {
    echo "Listing all users"
}

function uninstall {
    echo -e "${YELLOW} - Uninstalling web server (apache2, php and mariaDB)${ENDECHO}"
    sudo apt purge apache2 php mariadb-server -y
    outputParser $? "Web server uninstalled successfully." "An error occured while uninstalling web server. Reffer to error."
}

function menu() {
    PICKED_OPTION=""
    if [ -f /etc/apache2/.installedWithAWI ]; then
        #if true; then
        echo "Welcome to apache web server installer!"
        echo ""
        echo "Options:"
        echo "   1) Add new user"
        echo "   2) Remove existing user"
        echo "   3) List all users"
        echo "   4) Uninstall web server (apache2, php and mariaDB)"
        echo "   5) Exit"
        
        until [[ ${PICKED_OPTION} =~ ^[1-5]$ ]]; do
            read -rp "Select option [1-5]: " PICKED_OPTION
        done
        case "${PICKED_OPTION}" in
            1)
                addUser
            ;;
            2)
                removeUser
            ;;
            3)
                listUsers
            ;;
            4)
                uninstall
            ;;
            5)
                exit 0
            ;;
        esac
    else
        echo "Welcome to apache web server installer!"
        echo ""
        echo "Options:"
        echo "   1) Install web server (apache2, php and mariaDB)"
        echo "   2) Exit"
        
        until [[ ${PICKED_OPTION} =~ ^[1-2]$ ]]; do
            read -rp "Select option [1-2]: " PICKED_OPTION
        done
        case "${PICKED_OPTION}" in
            1)
                initialInstall
            ;;
            2)
                exit 0
            ;;
        esac
    fi
}

menu