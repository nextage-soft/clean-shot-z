# Feature Spec — S3 Backup: Auto Sync + Retention

> Trạng thái: SPEC — chưa implement. Ước lượng: 1.5-2 tuần (client SigV4 3 ngày, sync engine 4 ngày, UI + retention 3 ngày).
> Mục tiêu: mọi capture tự động backup lên S3-compatible storage (AWS S3 / Cloudflare R2 / MinIO), tự xoá bản remote sau N ngày.

## 1. Phạm vi

- **Auto upload**: ảnh (và tuỳ chọn video/GIF) sau khi lưu → tự đẩy lên bucket, chạy nền, offline thì xếp hàng chờ.
- **Retention**: bản trên S3 tự xoá sau N ngày (cấu hình, 0 = giữ vĩnh viễn). KHÔNG đụng file local.
- **Sync một chiều** (local → remote). KHÔNG phải two-way sync, không tải về, không share link (share link = backlog cloud riêng).

## 2. Quyết định kiến trúc

### 2.1 KHÔNG dùng AWS SDK — tự viết S3 REST client với SigV4
Lý do: aws-sdk-swift/Soto kéo theo hàng chục module (đi ngược zero-dependency của project; bài học KeyboardShortcuts còn đó — dependency có thể chết vì toolchain CLT). App chỉ cần 4 request: `PUT Object`, `DELETE Object`, `ListObjectsV2`, `HEAD Bucket`. SigV4 tự viết ~150 dòng bằng CryptoKit (HMAC-SHA256 sẵn trong OS).

```
s3-client.swift
  ├── struct S3Config { endpoint: URL; region: String; bucket: String;
  │                     pathStyle: Bool /* MinIO=true, AWS/R2=false */ }
  ├── func putObject(key:data:contentType:) async throws
  ├── func deleteObject(key:) async throws
  ├── func listObjects(prefix:continuationToken:) async throws -> ([S3Object], nextToken?)
  └── func headBucket() async throws          // Test Connection
s3-signer.swift
  └── SigV4: canonical request → string-to-sign → signing key
      (HMAC chain: AWS4+secret → date → region → "s3" → "aws4_request")
      Header: Authorization, x-amz-date, x-amz-content-sha256 (SHA256 payload)
```
- URLSession, TLS bắt buộc (reject http trừ localhost MinIO dev).
- Virtual-host style `https://{bucket}.{endpoint}` cho AWS/R2; path-style `https://{endpoint}/{bucket}` cho MinIO — toggle trong settings, auto-detect: endpoint chứa "amazonaws.com" hoặc "r2.cloudflarestorage.com" → virtual-host.

### 2.2 Credentials trong Keychain — KHÔNG UserDefaults
- `keychain-helper.swift`: `kSecClassGenericPassword`, service `com.tieuanhquoc.cleanshotz.s3`, account = "access-key" / "secret-key". Đọc 1 lần lúc cần, không cache ra biến toàn cục, không bao giờ log.
- Endpoint/region/bucket/prefix (không nhạy cảm) → UserDefaults như settings khác.

### 2.3 Sync engine — event-driven + queue bền
```
handleCaptured() / recording finalize
        │ (nếu backup enabled + đúng loại file)
        ▼
BackupSyncEngine.enqueue(fileURL)
        │  append vào queue (persist ngay xuống backup-queue.json)
        ▼
worker Task (serial, 1 upload 1 lúc):
   đọc file → putObject(key) → thành công: ghi manifest, pop queue
                             → lỗi: retry backoff 30s→2m→10m→30m (max giữ trong queue,
                               NWPathMonitor báo có mạng lại → wake worker ngay)
```
- **Key layout**: `{prefix}/{yyyy}/{MM}/{fileName}` — ví dụ `cleanshotz/2026/07/CleanShot Z 2026-07-14 at 10.30.45.png`. Tên file đã unique theo timestamp nên không cần chống ghi đè.
- **Manifest** `~/Library/Application Support/CleanShotZ/backup-manifest.json`: `[{key, fileName, size, uploadedAt}]` — nguồn sự thật cho retention client-side + hiển thị trạng thái. Ghi atomic (write temp + rename).
- **Queue** `backup-queue.json`: sống sót qua app restart; file trong queue bị user xoá trước khi upload → skip + pop.
- Upload buffer: đọc `Data(contentsOf:)` cho ảnh (<50MB OK); video dùng `URLSession uploadTask(fromFile:)` streaming. **Multipart upload = P2** (chỉ cần khi video >5GB — hiếm; single PUT chịu được tới 5GB theo spec S3).

### 2.4 Retention — client-side sweeper (default) + khuyến nghị lifecycle
- **Client-side (hoạt động với mọi provider kể cả MinIO)**: sweeper chạy lúc app launch + mỗi 12h (Timer): quét manifest, entry có `uploadedAt < now - N ngày` → `deleteObject(key)` → xoá khỏi manifest. Lỗi xoá (mất mạng) → thử lại lượt sau, không chặn.
- Trường hợp manifest lạc hậu (user cài lại máy): nút "Rebuild manifest" trong settings = `listObjects(prefix)` dựng lại từ `LastModified` remote.
- **Khuyến nghị trong UI**: nếu dùng AWS/R2, hiện tip "Có thể set Lifecycle rule trên bucket để tự xoá phía server — đáng tin hơn khi máy tắt lâu ngày" + link docs. App KHÔNG tự gọi PutBucketLifecycle (cần quyền admin bucket, ngoài scope).
- Lưu ý ghi rõ trong UI: retention chỉ xoá bản REMOTE; file local do History (30 ngày) và thư mục save của user tự quản.

## 3. UI — Preferences tab "Backup" mới (`settings-backup-tab-view.swift`)

```
[Section: S3 Storage]
  Enable backup            [toggle]
  Endpoint    [https://s3.ap-southeast-1.amazonaws.com     ]
  Region      [ap-southeast-1]      Bucket [my-screenshots]
  Key prefix  [cleanshotz]
  Access Key  [__________]          Secret Key [••••••••] (SecureField)
  Path-style URLs (MinIO) [toggle, auto]
  (Test Connection)  → toast "✓ Connected" / lỗi chi tiết (status + XML message)

[Section: Sync]
  Upload screenshots automatically   [toggle, on]
  Upload recordings (video/GIF)      [toggle, off — file to]
  Trạng thái: "Đã backup 132 file · 3 đang chờ · lần cuối 10:32"
  (Sync Now)   (Rebuild manifest)

[Section: Retention]
  Delete remote copies after [ 90 ] days   (0 = keep forever)
  footer: "Chỉ xoá bản trên S3. File trên máy không bị đụng tới.
           Dùng AWS/R2? Cân nhắc set Lifecycle rule phía bucket."
```
- Secret lưu Keychain ngay khi field mất focus; hiển thị lại dạng bullet, không bao giờ hiện plaintext sau khi lưu.
- Menu bar: thêm dòng trạng thái nhỏ khi có pending ("Backing up 3 files…") dưới History.

## 4. IAM policy mẫu (đưa vào docs cho user tự tạo key giới hạn quyền)
```json
{ "Version": "2012-10-17", "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::BUCKET", "arn:aws:s3:::BUCKET/cleanshotz/*"],
    "Condition": {"StringLike": {"s3:prefix": ["cleanshotz/*"]}}
}]}
```

## 5. Edge cases
1. **Clock skew** > 15 phút → S3 trả 403 `RequestTimeTooSkewed`: parse XML lỗi, retry 1 lần với `Date` header từ response server.
2. Tên file unicode/dấu tiếng Việt/space: key phải URI-encode đúng chuẩn SigV4 (encode từng path segment, space = `%20` KHÔNG phải `+`) — điểm dễ sai nhất của SigV4, viết unit test riêng.
3. Đổi bucket/prefix khi đang có queue: queue giữ config-at-enqueue? KHÔNG — đơn giản: queue chỉ giữ fileURL, config đọc lúc upload (file lên bucket mới). Manifest cũ giữ nguyên để retention vẫn xoá được bên bucket cũ? KHÔNG — retention chỉ chạy trên config hiện tại; đổi bucket → hiện cảnh báo "manifest reset, bản cũ trên bucket cũ không được quản lý nữa".
4. Secret sai/hết hạn: 403 liên tục → sau 3 lượt fail toàn queue, tạm dừng auto-sync + hiện badge lỗi trong Preferences, không retry vô hạn đốt pin.
5. File .cleanshotz: theo toggle screenshots (upload cùng — nó là sản phẩm chụp).
6. Máy ngủ giữa upload: URLSession task fail → retry theo backoff bình thường.
7. Retention N ngày < tuổi file đang trong queue (edge hiếm): upload xong sweeper lượt sau xoá — chấp nhận.

## 6. Files mới
| File | Trách nhiệm |
|---|---|
| `s3-signer.swift` | SigV4 canonical request + HMAC chain (CryptoKit) |
| `s3-client.swift` | put/delete/list/headBucket qua URLSession |
| `keychain-helper.swift` | get/set/delete generic password |
| `backup-sync-engine.swift` | queue worker, backoff, NWPathMonitor, manifest |
| `backup-queue-store.swift` | persist queue + manifest (atomic JSON) |
| `settings-backup-tab-view.swift` | UI tab Backup |
| (sửa) capture-coordinator, recording finalize | hook enqueue |

## 7. Test plan
- [ ] Unit: SigV4 ký đúng với bộ test vector chính thức của AWS (docs có sẵn examples).
- [ ] Unit: key encode với tên file "CleanShot Z 2026-07-14 at 10.30.45 (2).png" + tên có dấu tiếng Việt.
- [ ] E2E với MinIO local (docker, path-style) + R2 thật: upload ảnh → thấy object đúng key; Test Connection sai secret → báo lỗi rõ.
- [ ] Tắt wifi → chụp 3 tấm → queue 3 → bật wifi → tự upload đủ 3 trong <1 phút.
- [ ] Retention 0 ngày (test mode ẩn: phút thay ngày?) — set 1 ngày, chỉnh uploadedAt manifest lùi 2 ngày → sweeper xoá remote + manifest entry.
- [ ] Quit app khi đang queue 5 file → mở lại → queue còn, tự chạy tiếp.
- [ ] Secret không xuất hiện trong `defaults read`, log, hay crash report.

## 8. Unresolved questions
1. Anh dùng provider nào chính (AWS / R2 / MinIO self-host)? — quyết định default UI + test target đầu tiên.
2. Retention mặc định bao nhiêu ngày (đề xuất 90)?
3. Có cần upload cả thư mục History cũ khi bật lần đầu ("backfill") không, hay chỉ file mới từ lúc bật?
