#!/bin/bash
sudo rm -rf /etc/apache2/.installedWithAWI
sudo apt purge apache2 php mariadb-server -y
sudo apt autoremove -y