# Feature Spec — Record Video (MP4)

> Trạng thái: SPEC — chưa implement. Ước lượng: 2-3 tuần (P1 core 1.5 tuần, P2 polish 1 tuần).
> Tham chiếu code hiện có: `screen-capture-service.swift` (ScreenCaptureKit), `area-selection-*` (chọn vùng), `quick-access-overlay-controller.swift`, `scroll-capture-controller.swift` (pattern control panel nổi).

## 1. Mục tiêu

Quay màn hình ra file MP4 (H.264/HEVC) như CleanShot X: chọn vùng/window/fullscreen → quay → panel điều khiển → Stop → Quick Access → trim. Ưu tiên: ổn định, file gọn, không cần driver ảo cho system audio.

## 2. User flow

### 2.1 Bắt đầu quay
1. Entry: menu bar "Record Screen…" / hotkey (đề xuất ⌘⇧6, remap được trong Preferences → Shortcuts) / nút Record thêm vào action bar All-in-One.
2. Reuse overlay chọn vùng hiện có (`AreaSelectionController` mode `.allInOne` rút gọn): kéo vùng hoặc click window; fullscreen = phím F hoặc click nền.
3. Sau khi chốt vùng → **pre-record bar** nổi dưới vùng (pattern giống scroll capture panel):
   - Nút `● Record` (Enter), `✕` (Esc)
   - Toggle: 🎤 Mic (on/off), 🔊 System audio (on/off), con trỏ (show/hide)
   - Picker nhỏ: MP4 / GIF (GIF xem spec riêng)
4. Bấm Record → đếm ngược 3-2-1 (HUD to giữa vùng) → bắt đầu.

### 2.2 Trong khi quay
- Viền vùng quay: khung mảnh màu đỏ (window level .screenSaver, ignoresMouseEvents=true, **loại khỏi capture** bằng excludingOwnWindows như scroll capture).
- Menu bar icon đổi thành ● đỏ + timer; click icon → menu chỉ còn "Stop Recording ⌘⇧6", "Pause", "Cancel Recording".
- Control panel nhỏ nổi góc (kéo được): timer mm:ss, dung lượng ước tính, nút Pause/Resume, Stop, Cancel.
- Hotkey quay lại (⌘⇧6) khi đang quay = Stop (hành vi CleanShot).

### 2.3 Kết thúc
- Stop → finalize file → Quick Access card (thumbnail = frame đầu, badge thời lượng) với nút: Play (mở QuickTime), Copy path?, Trim, Pin?, Close. Save vào thư mục cấu hình, tên `CleanShot Z 2026-07-14 at 10.30.45.mp4`, ghi vào History (mở rộng filter thêm mp4/mov/gif — thumbnail qua AVAssetImageGenerator).
- Cancel → xoá file tạm, không lưu.

## 3. Kiến trúc kỹ thuật

### 3.1 Pipeline

```
SCStream (video sample buffers + system-audio sample buffers)
   │                         AVCaptureSession (mic) ──┐
   ▼                                                  ▼
RecordingStreamWriter: AVAssetWriter (.mp4)
   ├── AVAssetWriterInput video (H.264 | HEVC, realtime)
   ├── AVAssetWriterInput audio #1 (system audio AAC)
   └── AVAssetWriterInput audio #2 (mic AAC)   ← 2 track riêng, mix khi trim/export nếu cần
```

- **SCStream** thay vì SCScreenshotManager: `SCStreamConfiguration`:
  - `width/height` = vùng chọn * scale (pixel); vùng lẻ → làm tròn chẵn (encoder yêu cầu even).
  - `sourceRect` = vùng chọn (points, toạ độ display, top-left) — KHÔNG dùng crop-sau như screenshot vì video cần crop tại nguồn cho rẻ.
  - `minimumFrameInterval` = CMTime(1, fps) — fps setting 30/60.
  - `showsCursor` theo toggle; `capturesAudio = true` + `excludesCurrentProcessAudio = true` (macOS 13+, KHÔNG cần BlackHole).
  - `queueDepth` 8.
- **SCStreamOutput** delegate: nhận `CMSampleBuffer` type `.screen` và `.audio`; kiểm tra `SCStreamFrameInfo.status == .complete` mới append (bỏ frame idle/blank).
- **AVAssetWriter**: `expectsMediaDataInRealTime = true`; video settings `AVVideoCodecType.h264` (default) hoặc `.hevc` (setting); bitrate auto (`AVVideoQualityKey` không áp dụng — dùng `AVVideoAverageBitRateKey` ≈ width*height*fps*0.1 cho h264, *0.07 cho HEVC).
- **Session timing**: `startSession(atSourceTime:)` với PTS của frame đầu. **Pause** = flag bỏ append + lưu khoảng gap; khi Resume, offset mọi PTS sau đó đi `-gap` (giữ timeline liền mạch) — dùng `CMTimeSubtract`, quản lý trong RecordingStreamWriter.
- **Mic**: `AVCaptureSession` + `AVCaptureAudioDataOutput` → append vào input #2. (SCStream chỉ cho system audio; mic phải đường riêng.)

### 3.2 Files mới (kebab-case, mỗi file <200 dòng)
| File | Trách nhiệm |
|---|---|
| `recording-session-controller.swift` | State machine: idle→selecting→preRecord→countdown→recording→paused→finishing; own SCStream + panel + border window |
| `recording-stream-writer.swift` | AVAssetWriter wrapper: append video/audio, pause offset, finalize async |
| `recording-mic-capturer.swift` | AVCaptureSession mic → CMSampleBuffer callback |
| `recording-control-panel.swift` | SwiftUI panel (timer/size/pause/stop/cancel) — pattern ScrollCapturePanelView (Status ObservableObject riêng, tránh retain cycle như bug đã fix) |
| `recording-border-window.swift` | Khung đỏ quanh vùng quay |
| `recording-settings` (mở rộng SettingsStore) | fps, codec, mic default, systemAudio default, countdown on/off |

### 3.3 Coordinator
- `CaptureCoordinator.startRecording()` guard qua `sessionActive` (mở rộng: thêm `recordingController != nil`) — **mọi entry point chụp ảnh cũng phải chặn khi đang quay** (đã có pattern sessionActive).

## 4. Settings (Preferences → tab "Recording" mới)
- FPS: 30 (default) / 60
- Codec: H.264 (default, tương thích) / HEVC (nhỏ hơn ~35%)
- Countdown 3s: on/off
- Mic mặc định: off; System audio mặc định: on
- Hiện con trỏ: on

## 5. Permissions
- Screen Recording: đã có.
- **Microphone**: thêm `NSMicrophoneUsageDescription` vào Info.plist; xin lần đầu khi bật mic (`AVCaptureDevice.requestAccess(.audio)`); mic tier granted per-app bình thường.

## 6. Edge cases & xử lý
1. Disk đầy: theo dõi `AVAssetWriter.status == .failed` → stop + alert + giữ phần đã ghi nếu finalize được.
2. Display ngủ / khoá máy giữa chừng: SCStream báo error delegate → auto-stop + finalize.
3. Vùng quay trên màn hình bị rút (external unplug): SCStream stop → finalize + toast.
4. Quay quá dài: soft-limit cảnh báo ở 30 phút (setting), không hard-cut.
5. Frame drop: đếm frame status != complete; > 5% → log + hiện cảnh báo nhẹ sau khi xong.
6. Kích thước lẻ: làm tròn width/height xuống số chẵn gần nhất.
7. App own windows (panel, border): excludingOwnWindows như scroll capture — panel không dính vào video.
8. Pause dài > 1h: vẫn đúng nhờ PTS offset; test riêng.

## 7. Trim editor (P2 — sau khi core chạy)
- Window đơn giản: AVPlayerView + 2 slider handle (in/out) + nút Trim → `AVAssetExportSession` preset `AVAssetExportPresetPassthrough` + `timeRange` (không re-encode, nhanh, không mất chất lượng). Mute mic track / system track: bật tắt bằng audioMix khi export (re-encode audio only).

## 8. Test plan
- [ ] Quay area/window/fullscreen 10s mỗi loại → mở QuickTime OK, đúng vùng, đúng scale Retina.
- [ ] Mic + system audio cùng lúc → 2 track trong file (kiểm bằng `ffprobe`/QuickTime inspector).
- [ ] Pause 5s giữa video 15s → file 15s không có đoạn đứng hình.
- [ ] Đang quay bấm ⌘⇧4 → bị chặn (sessionActive).
- [ ] Cancel → không còn file tạm.
- [ ] Multi-display: quay vùng trên màn phụ, DPI khác nhau.
- [ ] 60fps HEVC 1 phút → kiểm tra dung lượng & CPU (< ~40% một core M-series).

## 9. Unresolved questions
1. Hotkey mặc định ⌘⇧6 hay ⌘⇧5 (đè macOS toolbar)?
2. Webcam overlay có nằm trong scope đợt đầu không (đề xuất: KHÔNG — P3)?
3. Click highlight / keystroke overlay: P3 (cần CGEventTap + Accessibility permission)?
