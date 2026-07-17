# Clean Shot Z — Project Overview & PDR

> Mục tiêu: viết lại CleanShot X (https://cleanshot.com) dạng app macOS cho nhu cầu cá nhân.
> Ngày nghiên cứu: 2026-07-14. Nguồn: cleanshot.com, cleanshot.com/features.
> Cập nhật scope 2026-07-14: video/GIF recording + cloud share link → BACKLOG. Trọng tâm: screenshot tools + annotation editor + OCR (ưu tiên cao). UI/UX: học theo CleanShot X (user đã quen thao tác).

## 1. CleanShot X là gì

App chụp/quay màn hình macOS thay thế tool built-in, ~50+ tính năng, bán one-time license, có Cloud (optional) để share link. Native macOS, hỗ trợ Apple Silicon.

## 2. Danh sách tính năng (đầy đủ, đã phân nhóm + độ ưu tiên)

### 2.1 Capture (P0 — core)
- Capture area / window / fullscreen
- Capture window kèm background, padding, transparency, shadow
- Scrolling capture (chụp nội dung dài hơn màn hình — stitch nhiều frame)
- Self-timer (chụp trễ)
- Crosshair + magnifier + freeze screen (chọn vùng chính xác, chụp object đang chuyển động)
- All-in-One mode: 1 hotkey ra overlay chọn mọi chế độ, nhập size, lock aspect ratio

### 2.2 Quick Access Overlay + History (P0 — điểm ăn tiền nhất của CleanShot)
- Sau khi chụp: thumbnail nổi góc màn hình → click để annotate, drag-drop, copy, save, swipe để dismiss
- Multi-display support
- Capture history: lưu ~1 tháng, filter, xoá

### 2.3 Annotate / Editor (P0)
- Pencil (auto-smoothing), highlighter, arrow (4 kiểu, có curved)
- Shapes: rect, filled rect, ellipse, line
- Text (7 style sẵn), counter/step numbers (cho tutorial)
- Crop (aspect ratio, edge snapping), blur (secure/smooth), pixelate, spotlight
- Ghép nhiều ảnh (drag-drop vào canvas)
- File format riêng `.cleanshot` — non-destructive editing (lưu layers)

### 2.4 Background tool (P1)
- 10 background sẵn + custom image, auto-balance spacing, aspect ratio preset cho social, padding

### 2.5 Screen recording (BACKLOG)
- MP4 (H.264) hoặc GIF; window / fullscreen / custom area
- Chỉnh quality, FPS, resolution
- Audio: mic + system audio
- Overlay: hiện click (màu/size/animation), hiện keystroke, webcam overlay (vị trí, shape)
- Ẩn/hiện cursor, timer, tự bật Do Not Disturb, ẩn desktop icons

### 2.6 Video editor (BACKLOG)
- Trim, đổi resolution/quality, volume/mute, stereo→mono

### 2.7 OCR (P0 — ưu tiên cao theo yêu cầu user)
- Chụp vùng → nhận text, xử lý on-device (Vision framework, hỗ trợ tiếng Việt)
- Copy thẳng vào clipboard sau khi nhận diện; giữ nguyên line break; hotkey riêng như CleanShot

### 2.8 Pin screenshot (P1)
- Ghim ảnh nổi always-on-top, chỉnh size/opacity/position, lock mode

### 2.9 Cloud / share link (BACKLOG)
- Upload → share link, self-destruct, password, tag, custom domain, team

### 2.10 Settings (P1)
- ~12 panel: hotkeys, format, save location, tên file, overlay behavior, recording defaults…

## 3. Tech stack đề xuất

### Quyết định: Native macOS (Swift) — KHÔNG dùng Electron/Tauri
Lý do: mọi tính năng cốt lõi (ScreenCaptureKit, system audio, global hotkey, overlay window, OCR on-device, hiệu năng recording) đều là API native; Electron làm chất lượng capture/recording và footprint tệ đi rõ rệt. CleanShot X thật cũng là native app.

### Stack chi tiết

| Thành phần | Công nghệ | Ghi chú |
|---|---|---|
| Ngôn ngữ | Swift 5.10+ | |
| UI | SwiftUI + AppKit | SwiftUI cho settings/editor; AppKit (NSWindow, NSPanel) cho overlay chọn vùng, pin window, quick-access — SwiftUI thuần không đủ kiểm soát window level/click-through |
| App shell | Menu bar app (`NSStatusItem`, `LSUIElement`) | Không dock icon |
| Screenshot | **ScreenCaptureKit** (`SCScreenshotManager`, macOS 14+) | Thay `CGWindowListCreateImage` đã deprecated |
| Recording | ScreenCaptureKit `SCStream` + AVFoundation (`AVAssetWriter`, H.264) | System audio lấy trực tiếp từ SCStream (macOS 13+), khỏi cần driver ảo kiểu BlackHole |
| GIF | Encode từ frame bằng ImageIO (`CGImageDestination`) | Hoặc ffmpeg nếu cần chất lượng/palette tốt hơn |
| Webcam overlay | AVFoundation `AVCaptureSession` | Composite vào stream |
| Click/keystroke overlay | `CGEventTap` (cần Accessibility permission) | Vẽ overlay window trên cùng |
| OCR | Vision framework (`VNRecognizeTextRequest`) | On-device, miễn phí, hỗ trợ tiếng Việt từ macOS 13 |
| Scrolling capture | Chụp nhiều frame khi scroll (scroll event giả lập bằng CGEvent) + stitch bằng feature matching (Vision `VNTranslationalImageRegistrationRequest`) | Phần khó nhất về thuật toán |
| Global hotkeys | Carbon `RegisterEventHotKey` tự viết (`global-hotkey-center.swift`) | Thư viện KeyboardShortcuts KHÔNG build được với Command Line Tools (macro `#Preview` cần Xcode) → tự implement, không dependency |
| Annotation editor | Canvas riêng bằng Core Graphics/Core Animation layers; model layer-based để non-destructive | Có thể tham khảo kiến trúc của Shottr/Annotate |
| Video trim | `AVAssetExportSession` | |
| Persistence | File-based + SQLite (GRDB) cho history | Format `.cleanshotz` = JSON layers + ảnh gốc (zip) |
| Settings | `UserDefaults` + SwiftUI Settings scene | |
| Cloud (BACKLOG) | Backend tuỳ chọn: Cloudflare R2/Workers hoặc S3 presigned URL | Chỉ cần nếu sau này muốn share link |
| Build | SPM + Command Line Tools (KHÔNG cần Xcode full — máy chỉ có CLT) | `scripts/build-and-bundle-app.sh` build + đóng gói .app + codesign bằng cert "Apple Development" (giữ TCC ổn định giữa các build) |
| Permissions | Screen Recording (TCC), Microphone, Accessibility (keystroke/click overlay, scrolling capture) | Phải làm onboarding xin quyền tử tế |

### Yêu cầu hệ thống đề xuất
- Target macOS 14 (Sonoma)+ → được dùng `SCScreenshotManager`, SCStream audio, Vision đầy đủ. Máy bạn đang chạy Darwin 27 (macOS 2026) nên không vấn đề.

### Tham khảo open-source
- **Kap** (github.com/wulkano/Kap) — recorder macOS, Electron (tham khảo UX, đừng tham khảo stack)
- **Shottr** — native, closed-source nhưng là benchmark UX tốt
- **Flameshot** — annotation UX (Qt, cross-platform)
- **Azayaka / QuickRecorder** (github.com/lihaoyun6/QuickRecorder) — open-source Swift + ScreenCaptureKit recorder, tham khảo code SCStream rất tốt

## 4. Nguyên tắc UI/UX: clone hành vi CleanShot X

User đã dùng quen CleanShot X → giữ nguyên các pattern thao tác, không sáng tạo lại:
- Menu bar icon + dropdown menu cùng cấu trúc (Capture Area / Window / Fullscreen / Scrolling / OCR / All-in-One / History / Preferences)
- Hotkey mặc định giống CleanShot (⌘⇧4-style area, có thể map lại trong Settings)
- Overlay chọn vùng: dim nền, crosshair + toạ độ + kích thước realtime, magnifier khi di chuột, kéo xong hiện nút xác nhận; Space để chuyển window mode; Esc huỷ
- Quick Access Overlay: thumbnail nổi góc dưới-trái, hover hiện nút (annotate/copy/save/close), drag thẳng vào app khác, swipe để dismiss
- Editor: toolbar trái (tool), thanh trên (style/color/size), canvas giữa — bố cục như CleanShot
- OCR: chọn vùng → text vào clipboard ngay + notification "Text copied"
- Settings: dạng tab panels như CleanShot (General, Shortcuts, Screenshots, Annotate, OCR, Advanced…)

Khi implement màn hình nào thì chụp/đối chiếu màn hình tương ứng của CleanShot X thật (user đang cài sẵn) làm spec.

## 5. Roadmap (đã cập nhật theo scope 2026-07-14)

| Phase | Nội dung | Ước lượng |
|---|---|---|
| M1 | Menu bar app + global hotkey + capture area/window/fullscreen (overlay chọn vùng kiểu CleanShot) + save/copy + Quick Access overlay | 1-2 tuần |
| M2 | Annotation editor: arrow, pencil, highlighter, shapes, text, counter, blur/pixelate, spotlight, crop, undo/redo | 2-3 tuần |
| M3 | **OCR** (hotkey riêng, copy clipboard, tiếng Việt + Anh), pin screenshot, self-timer, capture history | 1-2 tuần |
| M4 | Scrolling capture, background tool, window capture kèm background/padding/shadow, file format non-destructive | 2-3 tuần |

### Backlog (đã có spec chi tiết, chưa implement)
- **Record video MP4** → [feature-spec-video-recording.md](feature-spec-video-recording.md)
- **GIF recording/export** → [feature-spec-gif-recording.md](feature-spec-gif-recording.md)
- **Chữ ký bằng trackpad (Sign)** → [feature-spec-trackpad-signature.md](feature-spec-trackpad-signature.md)
- **S3 backup: auto sync + retention** → [feature-spec-s3-backup-sync.md](feature-spec-s3-backup-sync.md)

### Backlog (chưa có spec)
- Click/keystroke overlay, webcam overlay (chỉ có ý nghĩa khi có recording)
- Cloud share link
- Multi-image composition nâng cao

## 6. Unresolved questions
- Chỉ cần macOS 14+ đúng không? (mặc định: có)
- OCR: cần thêm ngôn ngữ nào ngoài Việt + Anh?
