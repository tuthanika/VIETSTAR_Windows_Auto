# Auto ISO Downloader & Uploader

## Giới thiệu
Bộ script PowerShell này tự động:
- Lấy link ISO từ forum rg-adguard hoặc cloud mail.ru
- Phân loại theo rules (`FILE_CODE_RULES`)
- Kiểm tra tồn tại trên remote (rclone)
- Tải bằng aria2
- Upload bằng rclone
- Quản lý rotation (move bản cũ sang `old`, xóa thừa)

Quy trình được điều phối bởi orchestrator `build-list.ps1` và uploader `uploader.ps1`.

---

## Cấu trúc file
````
scripts/ 
rules.ps1 
redirect.ps1 
downloader.ps1 
threads.ps1 
go-link.ps1 
check-exists.ps1 
uploader.ps1 
build-list.ps1
````

---

## Map chức năng

| File              | Chức năng chính                                                                 | Input                                                                 | Output                                                                 |
|-------------------|---------------------------------------------------------------------------------|----------------------------------------------------------------------|------------------------------------------------------------------------|
| **rules.ps1**     | Phân loại file theo `FILE_CODE_RULES`                                           | `-FileNameA`                                                          | Tên folder (chuỗi)                                                     |
| **redirect.ps1**  | Theo dõi redirect hop-by-hop để lấy URL cuối                                    | `-StartUrl`                                                           | URL cuối (chuỗi)                                                       |
| **downloader.ps1**| Gọi PHP `downloader.php`, parse output, phân loại folder, check-exists, ghi pipe| `-SourceUrl`, `-PipePath`                                             | Ghi thêm dòng vào pipe `links.final.txt`                               |
| **threads.ps1**   | Lấy danh sách thread từ section forum, áp dụng filter và rules                 | `-SectionUrl`, `-ThreadFilter`                                        | In ra `Folder|ThreadUrl`                                               |
| **go-link.ps1**   | Lấy go-link từ thread                                                          | `-ThreadUrl`                                                          | Go-link đầu tiên (chuỗi)                                               |
| **check-exists.ps1**| Kiểm tra file đã tồn tại trên remote, quyết định upload/skip                  | `-Mode`, `-Key`, `-Folder`, `-FileNameA`                             | JSON `{status, key_date, filenameB, folder, filenameB_delete}`         |
| **uploader.ps1**  | Đọc pipe, xử lý download bằng aria2 và upload bằng rclone                      | `-PipePath`                                                           | Thực hiện download/upload, log chi tiết                                |
| **build-list.ps1**| Orchestrator: đọc `link.txt`, gọi các module để tạo pipe `links.final.txt`      | Không có param, đọc `link.txt` trong repo                             | File `links.final.txt` chứa danh sách link cần xử lý                   |

---

## Quy trình hoạt động

1. **Chuẩn bị**  
   - Tạo file `link.txt` trong repo, mỗi dòng là một nguồn link:  
     - Link forum section (`https://forum.rg-adguard.net/forums/...`)  
     - Link thread (`https://forum.rg-adguard.net/threads/...`)  
     - Link cloud mail.ru (`https://cloud.mail.ru/...`)  
   - Có thể thêm filter hoặc downloadKey sau dấu `|`.

   Ví dụ:
   
`````
https://cloud.mail.ru/public/H4bu/Sy7P54iuw/.iso 
https://forum.rg-adguard.net/forums/windows-7.72/ 
https://forum.rg-adguard.net/forums/windows-8-1.73/|8.1multi|*.iso
`````

2. **Build list**  
- Chạy:
  ```powershell
  pwsh -File scripts/build-list.ps1
  ```
- Script sẽ gọi lần lượt:
  - `threads.ps1` → lấy thread
  - `go-link.ps1` → lấy go-link
  - `redirect.ps1` → resolve link cuối
  - `downloader.ps1` → parse file, phân loại folder, check-exists, ghi pipe
- Kết quả: file `links.final.txt`.

3. **Upload**  
- Chạy:
  ```powershell
  pwsh -File scripts/uploader.ps1 -PipePath "C:\RUN\links.final.txt"
  ```
- Script sẽ:
  - Skip file tồn tại (`status=exists`)
  - Move bản cũ sang `old`
  - Xóa thừa nếu vượt `MAX_FILE`
  - Download file mới bằng aria2 (sử dụng `$env:ARIA2_OPTS`)
  - Upload file mới bằng rclone (sử dụng `$env:RCLONE_FLAG`)

---

## Biến môi trường cần thiết

- `FORUM_COOKIE`, `FORUM_UA` → để login forum  
- `FILE_CODE_RULES` → JSON rules phân loại folder  
- `REMOTE_NAME`, `REMOTE_TARGET`, `RCLONE_CONFIG_PATH` → cấu hình rclone  
- `ARIA2_OPTS` → option cho aria2  
- `RCLONE_FLAG` → option cho rclone  
- `MAX_FILE` → số lượng file tối đa giữ lại mỗi folder  

---

## YAML CI/CD

Trong GitHub Actions, bạn chỉ cần 2 step:

```yaml
- name: Build list
shell: pwsh
run: |
 & "$env:REPO_PATH\scripts\build-list.ps1"

- name: Run uploader
shell: pwsh
run: |
 & "$env:REPO_PATH\scripts\uploader.ps1" -PipePath "$env:SCRIPT_PATH\links.final.txt"

---
