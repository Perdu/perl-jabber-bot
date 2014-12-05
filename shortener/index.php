<?php
function RandomString()
{
    $characters = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    $randstring = '';
    for ($i = 0; $i < 4; $i++) {
        $randstring .= $characters[rand(0, strlen($characters))];
    }
    return $randstring;
}

if (isset($_GET["url"])) {
    $url = base64_decode($_GET["url"]);
    if (substr($url, 0, 7) == "http://" || substr($url, 0, 8) == "https://") {
	$filename = RandomString();
	$file = fopen($filename, 'w') or die("Unable to create $filename");
	fwrite($file, "<html><head><meta http-equiv='refresh' content='0; URL=\"" . htmlspecialchars($url) . "\"'></head><body></body></html>");
	fclose($file);
	echo $filename;
	return;
    }
}
echo "hi";

?>