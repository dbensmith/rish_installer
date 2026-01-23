<?php

$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
if (stripos($ua, 'merbah3266/rish') === false) {
    header('Location: https://github.com/merbah3266/rish_installer', true, 302);
    exit;
}

function send_error($message, $code = 400) {
    http_response_code($code);
    header('Content-Type: text/plain; charset=utf-8');
    header('X-Rish-Status: error');
    header('X-Rish-Message: ' . $message);
    exit($message);
}

$headers   = getallheaders();
$requested = $_SERVER['HTTP_X_FILE'] ?? $headers['X-File'] ?? null;
$apkUrl    = $_SERVER['HTTP_X_DIRECTURL'] ?? $headers['X-DirectURL'] ?? null;

if (!$requested) send_error("Missing 'X-File' header.", 400);
if (!$apkUrl) send_error("Missing 'X-DirectURL' header.", 400);

switch ($requested) {
    case 'rish':
        $apkPath = 'assets/rish';
        break;
    case 'dex':
        $apkPath = 'assets/rish_shizuku.dex';
        break;
    default:
        send_error("Invalid 'X-File' value. Must be 'rish' or 'dex'.", 400);
}

$cacheTtl  = 20;
$cacheKey  = hash('sha256', $apkUrl);
$cacheFile = sys_get_temp_dir() . "/apk_cache_$cacheKey.apk";
$cacheTime = $cacheFile . '.time';

if (file_exists($cacheFile) && file_exists($cacheTime)) {
    if (time() - (int)file_get_contents($cacheTime) > $cacheTtl) {
        @unlink($cacheFile);
        @unlink($cacheTime);
    }
}

if (!file_exists($cacheFile)) {
    $apkData = @file_get_contents($apkUrl);
    if ($apkData === false) send_error("Failed to download APK.", 500);
    file_put_contents($cacheFile, $apkData, LOCK_EX);
    file_put_contents($cacheTime, time(), LOCK_EX);
}

$zip = new ZipArchive;
if ($zip->open($cacheFile) !== TRUE) send_error("Failed to open APK file.", 500);
if (!$zip->locateName($apkPath)) {
    $zip->close();
    send_error("File '$apkPath' not found in APK.", 404);
}

$stream = $zip->getStream($apkPath);
if ($stream === false) {
    $zip->close();
    send_error("Failed to read file '$apkPath'.", 500);
}

$data = stream_get_contents($stream);
fclose($stream);
$zip->close();

$crc32  = hash('crc32b', $data);
$md5    = md5($data);
$sha1   = sha1($data);
$sha256 = hash('sha256', $data);
$sha384 = hash('sha384', $data);
$sha512 = hash('sha512', $data);

$xor = 0;
$len = strlen($data);
for ($i = 0; $i < $len; $i++) {
    $xor ^= ord($data[$i]);
}
$qxor = sprintf('%02x', $xor);

$dbhash = md5($sha1);

http_response_code(200);
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . basename($apkPath) . '"');
header('X-Rish-Status: ok');

header('X-Hash-crc32: '  . $crc32);
header('X-Hash-md5: '    . $md5);
header('X-Hash-sha1: '   . $sha1);
header('X-Hash-sha256: ' . $sha256);
header('X-Hash-sha384: ' . $sha384);
header('X-Hash-sha512: ' . $sha512);
header('X-Hash-q-xor: '  . $qxor);
header('X-Hash-db-hash: '. $dbhash);

echo $data;
exit;