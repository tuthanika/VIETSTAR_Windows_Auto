<?php

$i = $_GET['url'] ?? '';
if ($i === '') {
    die("Thiếu tham số url");
}

// Tách index ra khỏi URL
$parts = explode('/', rtrim($i, '/'));
$last = end($parts);

if (ctype_digit($last)) {
    $index = intval($last);
    array_pop($parts); // bỏ phần index ra khỏi URL
    $baseUrl = implode('/', $parts);
} else {
    $index = 0;
    $baseUrl = $i;
}

// Lấy danh sách file từ URL gốc (không có index)
$dwnld_list = GetAllFiles($baseUrl);
if ($dwnld_list === false || empty($dwnld_list)) {
    die("Không lấy được danh sách file từ $baseUrl");
}

if (!isset($dwnld_list[$index])) {
    die("File thứ $index không tồn tại trong folder");
}

$redirect = $dwnld_list[$index]->download_link;
$headers = @get_headers($redirect);

$file = $redirect;
if (ob_get_level()) {
    ob_end_clean();
}
header('Content-Description: File Transfer');
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename=' . basename(parse_url($file, PHP_URL_PATH)));
header('Content-Transfer-Encoding: binary');
header('Expires: 0');
header('Cache-Control: must-revalidate');
header('Pragma: public');
if ($headers && isset($headers[4])) header($headers[4]);
readfile($file);
exit;

/* =========================
   Structures and functions
   ========================= */

class CMFile {
    public $name = "";
    public $output = "";
    public $link = "";
    public $download_link = "";
    function __construct($name, $output, $link, $download_link) {
        $this->name = $name;
        $this->output = $output;
        $this->link = $link;
        $this->download_link = $download_link;
    }
}

function GetAllFiles($link, $folder = "") {
    global $base_url, $id;
    $page = http_get(pathcombine($link, $folder));
    if ($page === false) { echo "Error $link\r\n"; return false; }

    $mainfolder = GetMainFolder($page);
    if ($mainfolder === false) { echo "Cannot get main folder $link\r\n"; return false; }

    if (!$base_url) $base_url = GetBaseUrl($page);
    if (!$id && preg_match('~\/public\/([A-Za-z0-9_\-\/]+)~', $link, $match)) $id = $match[1];

    $cmfiles = array();
    if (isset($mainfolder["name"]) && $mainfolder["name"] == "/") $mainfolder["name"] = "";

    foreach ($mainfolder["list"] as $item) {
        if ($item["type"] == "folder") {
            $files_from_folder = GetAllFiles($link, pathcombine($folder, rawurlencode(basename($item["name"]))));
            if (is_array($files_from_folder)) {
                foreach ($files_from_folder as $file) {
                    if ($mainfolder["name"] != "")
                        $file->output = $mainfolder["name"] . "/" . $file->output;
                }
                $cmfiles = array_merge($cmfiles, $files_from_folder);
            }
        } else {
            $fileurl = pathcombine($folder, rawurlencode($item["name"]));
            if ($id && strpos($id, $fileurl) !== false) $fileurl = "";
            $cmfiles[] = new CMFile(
                $item["name"],
                pathcombine($mainfolder["name"], $item["name"]),
                pathcombine($link, $fileurl),
                pathcombine($base_url, $id, $fileurl)
            );
        }
    }
    return $cmfiles;
}

function GetMainFolder($page) {
    // match object serverSideFolders
    if (preg_match('~"serverSideFolders"\s*:\s*(\{.*?"list"\s*:\s*\[.*?\].*?\})~s', $page, $match)) {
        return json_decode($match[1], true);
    }
    return false;
}

function GetBaseUrl($page) {
    // match weblink_get.url
    if (preg_match('~"weblink_get"\s*:\s*\{.*?"url"\s*:\s*"(https:[^"]+)~s', $page, $match)) {
        return $match[1];
    }
    return false;
}

function http_get($url) {
    $opts = [
        'http' => [
            'method' => "GET",
            'header' => "User-Agent: Mozilla/5.0\r\n",
            'timeout' => 20
        ]
    ];
    $ctx = stream_context_create($opts);
    return @file_get_contents($url, false, $ctx);
}

function pathcombine() {
    $result = "";
    foreach (func_get_args() as $arg) {
        if ($arg !== '') {
            if ($result && substr($result, -1) != "/") $result .= "/";
            $result .= $arg;
        }
    }
    return $result;
}

?>
