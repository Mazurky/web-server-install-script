<?php 
const DB_SERVER = 'localhost';
const DB_USERNAME = 'admin';
const DB_PASSWORD = 'admin';
const DB_NAME = 'admin';

$db_handler = new mysqli(DB_SERVER, DB_USERNAME, DB_PASSWORD, DB_NAME);
if ($db_handler->connect_error) {
    die("ERROR Connection failed: " . $db_handler->connect_error);
}

echo "Mysql a PHP funguje!";
echo phpinfo();


?>