<?php 
const DB_SERVER = 'localhost';
const DB_USERNAME = 'webadmin';
const DB_PASSWORD = 'webadmin';
const DB_NAME = 'webadmin';

$db_handler = new mysqli(DB_SERVER, DB_USERNAME, DB_PASSWORD, DB_NAME);
if ($db_handler->connect_error) {
    die("ERROR Connection failed: " . $db_handler->connect_error);
}

echo "Mysql a PHP funguje!";
echo phpinfo();


?>