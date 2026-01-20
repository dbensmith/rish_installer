<?php

function send_error($message, $code = 400) {
    http_response_code($code);
    header('Content-Type: text/plain; charset=utf-8');
    header('X-Rish-Status: error');
    header('X-Rish-Message: ' . $message);
    exit($message);
}

$headers = getallheaders();
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

$apkFile = tempnam(sys_get_temp_dir(), 'apk_');
$apkData = @file_get_contents($apkUrl);
if ($apkData === false) send_error("Failed to download APK from '$apkUrl'.", 500);
file_put_contents($apkFile, $apkData);

$zip = new ZipArchive;
if ($zip->open($apkFile) !== TRUE) send_error("Failed to open APK file.", 500);

if (!$zip->locateName($apkPath)) send_error("File '$apkPath' not found in APK.", 404);

http_response_code(200);
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . basename($apkPath) . '"');
header('X-Rish-Status: ok');

$stream = $zip->getStream($apkPath);
if ($stream === false) send_error("Failed to read file '$apkPath' from APK.", 500);

fpassthru($stream);

$zip->close();
unlink($apkFile);
exit;
?>