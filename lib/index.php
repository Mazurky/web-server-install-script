<?php 
const DB_SERVER = 'localhost';
const DB_USERNAME = '%user%';
const DB_PASSWORD = '%password%';
const DB_NAME = '%databaseName%';

$db_handler = new mysqli(DB_SERVER, DB_USERNAME, DB_PASSWORD, DB_NAME);
if ($db_handler->connect_error) {
    die("ERROR Connection failed: " . $db_handler->connect_error);
}

echo "Mysql a PHP funguje!<br>";
$website_Owner = "%user%" . " " . "%password%";
echo $website_Owner;
echo "<br>";
echo phpinfo();

?>