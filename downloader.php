<?php
// Cho phép chạy từ CLI hoặc qua web
if (php_sapi_name() === 'cli') {
    $i = $argv[1] ?? '';
} else {
    $i = $_GET['url'] ?? '';
}
if ($i === '') die("Thiếu tham số url");

// Tách index hoặc filename
$parts = explode('/', rtrim($i, '/'));
$last  = end($parts);

$index    = null;
$filename = null;
$baseUrl  = $i;

// Nếu có index
if (ctype_digit($last)) {
    $index = intval($last);
    array_pop($parts);
    $baseUrl = implode('/', $parts);
}
// Nếu có dấu chấm → filename hoặc wildcard
elseif (strpos($last, '.') !== false) {
    // wildcard *.iso / *.exe
    if (preg_match('/^\*\.(iso|exe)$/i', $last, $m)) {
        $ext = strtolower($m[1]);
        array_pop($parts);                // bỏ phần *.iso
        $baseUrl = implode('/', $parts);  // folder gốc

        $dwnld_list = GetAllFiles($baseUrl);
        if ($dwnld_list === false || empty($dwnld_list)) die("Không lấy được danh sách file từ $baseUrl");

        header('Content-Type: text/plain; charset=utf-8');
        foreach ($dwnld_list as $f) {
            if (strtolower(pathinfo($f->name, PATHINFO_EXTENSION)) === $ext) {
                echo $f->download_link."\n";
            }
        }
        exit;
    } else {
        // filename cụ thể
        $filename = $last;
        array_pop($parts);
        $baseUrl = implode('/', $parts);
    }
}

// Lấy danh sách file
$dwnld_list = GetAllFiles($baseUrl);
if ($dwnld_list === false || empty($dwnld_list)) die("Không lấy được danh sách file từ $baseUrl");

// Nếu có index
if ($index !== null) {
    if ($index === 0) {
        // Hiện menu HTML
        echo "<h3>Danh sách file trong folder:</h3>";
        foreach ($dwnld_list as $idx => $file) {
            $num  = $idx + 1;
            $link = htmlspecialchars($_SERVER['PHP_SELF']."?url=".$baseUrl."/".$num);
            echo "<a href=\"$link\">File $num: ".$file->name."</a><br>";
        }
        exit;
    } else {
        $fileIndex = $index - 1;
        if (!isset($dwnld_list[$fileIndex])) die("File thứ $index không tồn tại");
        $redirect = $dwnld_list[$fileIndex]->download_link;

        if (php_sapi_name() === 'cli') {
            header('Content-Type: text/plain; charset=utf-8');
            echo $redirect;
        } else {
            header("Location: $redirect");
        }
        exit;
    }
}

// Nếu có filename cụ thể
if ($filename !== null) {
    $target = null;
    foreach ($dwnld_list as $f) {
        if (strcasecmp($f->name, $filename) === 0) {
            $target = $f;
            break;
        }
    }
    if (!$target) die("Không tìm thấy file tên '$filename'");
    $redirect = $target->download_link;

    if (php_sapi_name() === 'cli') {
        header('Content-Type: text/plain; charset=utf-8');
        echo $redirect;
    } else {
        header("Location: $redirect");
    }
    exit;
}

// Không có index/filename → xuất plain text danh sách link trực tiếp
header('Content-Type: text/plain; charset=utf-8');
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
?>
