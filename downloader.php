<?php
// Cho phép chạy từ CLI hoặc qua web
if (php_sapi_name() === 'cli') {
    $input = $argv[1] ?? '';
} else {
    $input = $_GET['url'] ?? '';
}
if ($input === '') die("Thiếu tham số url");

// Chuẩn hóa và tách phần cuối
$input = rtrim($input, '/');
$parts = explode('/', $input);
$last  = end($parts);

// Xác định selector: index hoặc filename
$selector = null;
$baseUrl  = $input;

if (ctype_digit($last)) {
    $selector = intval($last); // index
    array_pop($parts);
    $baseUrl = implode('/', $parts);
} elseif (strpos($last, '.') !== false) {
    $selector = $last; // filename
    array_pop($parts);
    $baseUrl = implode('/', $parts);
}

// Lấy danh sách file
$dwnld_list = GetAllFiles($baseUrl);
if ($dwnld_list === false || empty($dwnld_list)) {
    http_plain();
    die("Không lấy được danh sách file từ $baseUrl");
}

// Nếu selector là index
if (is_int($selector)) {
    if ($selector === 0) {
        http_html();
        echo "<h3>Danh sách file trong folder:</h3>";
        foreach ($dwnld_list as $idx => $file) {
            $num  = $idx + 1;
            $link = htmlspecialchars($_SERVER['PHP_SELF']."?url=".$baseUrl."/".$num);
            echo "<a href=\"$link\">File $num: ".htmlspecialchars($file->name)."</a><br>";
        }
        exit;
    } else {
        $fileIndex = $selector - 1;
        if (!isset($dwnld_list[$fileIndex])) die("File thứ $selector không tồn tại");
        header("Location: ".$dwnld_list[$fileIndex]->download_link);
        exit;
    }
}

// Nếu selector là filename
if (is_string($selector) && $selector !== '') {
    $target = find_file_by_name($dwnld_list, $selector);
    if (!$target) die("Không tìm thấy file tên '$selector'");
    header("Location: ".$target->download_link);
    exit;
}

// Không có selector → xuất plain text danh sách link
http_plain();
foreach ($dwnld_list as $file) {
    echo $file->download_link."\n";
}
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
    static $base_url = null;
    static $id = null;

    $page = http_get(pathcombine($link, $folder));
    if ($page === false || $page === '') return false;

    $mainfolder = GetMainFolder($page);
    if ($mainfolder === false || !isset($mainfolder['list']) || !is_array($mainfolder['list'])) return false;

    if ($base_url === null) $base_url = GetBaseUrl($page);
    if ($id === null && preg_match('~\/public\/([A-Za-z0-9_\-\/]+)~', $link, $match)) {
        $id = $match[1];
    }

    $cmfiles = array();
    if (isset($mainfolder["name"]) && $mainfolder["name"] == "/") $mainfolder["name"] = "";

    foreach ($mainfolder["list"] as $item) {
        if (!isset($item["type"], $item["name"])) continue;
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
    if (preg_match('~"serverSideFolders"\s*:\s*(\{.*?"list"\s*:\s*\[.*?\].*?\})~s', $page, $match)) {
        return json_decode($match[1], true);
    }
    return false;
}

function GetBaseUrl($page) {
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

function http_plain() {
    if (php_sapi_name() !== 'cli') {
        header('Content-Type: text/plain; charset=utf-8');
    }
}

function http_html() {
    if (php_sapi_name() !== 'cli') {
        header('Content-Type: text/html; charset=utf-8');
    }
}

function find_file_by_name(array $list, $name) {
    foreach ($list as $f) {
        if ($f->name === $name) return $f;
    }
    $lname = mb_strtolower($name, 'UTF-8');
    foreach ($list as $f) {
        if (mb_strtolower($f->name, 'UTF-8') === $lname) return $f;
    }
    return null;
}
?>
