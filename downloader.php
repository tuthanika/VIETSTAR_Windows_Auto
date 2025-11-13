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
    $index = null; // không có index
    $baseUrl = $i;
}

// Lấy danh sách file từ URL gốc (không có index)
$dwnld_list = GetAllFiles($baseUrl);
if ($dwnld_list === false || empty($dwnld_list)) {
    die("Không lấy được danh sách file từ $baseUrl");
}

// Nếu có index
if ($index !== null) {
    if ($index === 0) {
        // Nén zip toàn bộ folder
        $zip = new ZipArchive();
        $zipname = tempnam(sys_get_temp_dir(), "mailru").".zip";
        if ($zip->open($zipname, ZipArchive::CREATE) !== TRUE) {
            die("Không tạo được file zip");
        }
        foreach ($dwnld_list as $file) {
            $content = @file_get_contents($file->download_link);
            if ($content !== false) {
                $zip->addFromString($file->name, $content);
            }
        }
        $zip->close();

        if (ob_get_level()) ob_end_clean();
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="folder.zip"');
        header('Content-Length: ' . filesize($zipname));
        readfile($zipname);
        unlink($zipname);
        exit;
    } else {
        // Tải file theo index (1 = file đầu tiên, 2 = file thứ hai, ...)
        $fileIndex = $index - 1;
        if (!isset($dwnld_list[$fileIndex])) {
            die("File thứ $index không tồn tại trong folder");
        }
        $redirect = $dwnld_list[$fileIndex]->download_link;
        $headers = @get_headers($redirect);

        $file = $redirect;
        if (ob_get_level()) ob_end_clean();
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
    }
}

// Nếu không có index → liệt kê danh sách link tải
echo "<h3>Danh sách file trong folder:</h3>";
foreach ($dwnld_list as $idx => $file) {
    $num = $idx + 1;
    $link = htmlspecialchars($_SERVER['PHP_SELF']."?url=".$baseUrl."/".$num);
    echo "<a href=\"$link\">File $num: ".$file->name."</a><br>";
}
echo "<br><a href=\"".htmlspecialchars($_SERVER['PHP_SELF']."?url=".$baseUrl."/0")."\">Tải tất cả (zip)</a>";

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
    if ($page === false) { return false; }

    $mainfolder = GetMainFolder($page);
    if ($mainfolder === false) { return false; }

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
