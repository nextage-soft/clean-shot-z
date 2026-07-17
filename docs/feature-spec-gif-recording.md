# Feature Spec — GIF Recording & Export

> Trạng thái: SPEC — chưa implement. Phụ thuộc: feature-spec-video-recording.md (dùng chung pipeline quay).
> Ước lượng: 3-4 ngày SAU KHI video recording xong (phần lớn là converter).

## 1. Mục tiêu

Hai đường ra GIF, cùng một converter:
1. **Record GIF trực tiếp**: pre-record bar chọn "GIF" → quay như video → Stop → tự convert → file .gif.
2. **Export GIF từ video đã quay**: Quick Access card của video / History → "Export GIF…".

## 2. Quyết định kiến trúc: quay MP4 tạm rồi convert (KHÔNG encode GIF realtime)

Lý do:
- Encode GIF realtime giữ toàn bộ frame trong RAM hoặc phải ghi incremental — CGImageDestination GIF không finalize-incremental tốt với hàng nghìn frame.
- Quay MP4 tạm (H.264, nhanh, ổn định) rồi convert cho phép: chọn lại fps/size sau, tái dùng 100% pipeline video, retry convert không mất bản quay.
- Trade-off chấp nhận: tốn 1 lần decode + disk tạm.

```
SCStream → AVAssetWriter (.mp4 tạm trong ~/Library/Caches/CleanShotZ/)
             │ Stop
             ▼
GifEncoder.convert(videoURL, options) → .gif  → (xoá mp4 tạm nếu là chế độ GIF trực tiếp)
```

## 3. GifEncoder — thiết kế chi tiết

File mới: `gif-encoder.swift` (+ `gif-export-options-view.swift` cho dialog).

### 3.1 API
```swift
struct GifOptions {
    var fps: Int = 12            // 8/10/12/15
    var maxWidth: CGFloat = 800  // px, giữ tỉ lệ; 480/800/1000/original
    var loopForever = true
    var timeRange: CMTimeRange?  // dùng khi export từ video có trim
}
enum GifEncoder {
    static func convert(videoURL: URL, to outputURL: URL, options: GifOptions,
                        progress: @escaping (Double) -> Void) async throws
}
```

### 3.2 Pipeline (streaming, RAM phẳng)
1. `AVAssetReader` + `AVAssetReaderTrackOutput` (BGRA) đọc **tuần tự** — không dùng AVAssetImageGenerator (seek từng frame chậm và leak memory với video dài).
2. Sample fps: giữ frame khi `presentationTime >= nextKeepTime` (nextKeepTime += 1/fps) — drop phần còn lại.
3. Mỗi frame giữ lại: CVPixelBuffer → CGImage → downscale về maxWidth (CGContext, interpolation .medium là đủ cho GIF).
4. Append ngay vào `CGImageDestination` (type `UTType.gif`), frame properties:
   - `kCGImagePropertyGIFDelayTime` = 1/fps (lưu ý: nhiều viewer làm tròn 0.02s — dùng `kCGImagePropertyGIFUnclampedDelayTime` kèm theo)
   - GIF properties toàn cục: `kCGImagePropertyGIFLoopCount = 0` (lặp vô hạn)
5. `CGImageDestinationFinalize`. Progress = framesDone/framesEstimated (duration*fps).
6. Chạy trong `Task.detached(priority: .userInitiated)`; UI hiện progress trong Quick Access card (thanh mảnh) hoặc HUD.

### 3.3 Chất lượng & giới hạn (phải ghi rõ trong UI)
- ImageIO tự sinh palette 256 màu per-frame, KHÔNG dithering tốt như gifski → gradient sẽ có banding. Chấp nhận v1; ghi backlog: tích hợp thư viện gifski (Rust/C API) nếu cần chất lượng cao.
- Ước tính dung lượng hiển thị trước khi convert: `~ width*height*fps*duration*0.07 bytes` (heuristic, hiện "~4.2 MB").
- Cảnh báo khi duration > 30s hoặc kết quả ước tính > 25MB.

## 4. UX

### 4.1 Record GIF trực tiếp
- Pre-record bar (spec video §2.1): segmented `MP4 | GIF`. Chọn GIF → fps mặc định 12, tự tắt audio toggles (GIF không tiếng — disable mờ 2 nút audio).
- Stop → toast "Converting to GIF…" + progress → Quick Access card (.gif) — Copy (copy file vào clipboard dạng file URL + GIF data), Save đã tự lưu, Drag OK.

### 4.2 Export từ video
- Quick Access video card + History context menu: "Export GIF…" → sheet nhỏ: fps (8/10/12/15), max width (480/800/1000/Full), preview ước tính dung lượng, nút Export → NSSavePanel.

## 5. Settings (Preferences → Recording)
- GIF fps mặc định: 12
- GIF max width mặc định: 800px

## 6. Edge cases
1. Video HEVC input: AVAssetReader decode bình thường (hệ decode lo).
2. Video dài (>2 phút) chọn GIF: confirm dialog "GIF sẽ rất nặng, tiếp tục?".
3. Convert fail giữa chừng (disk đầy): xoá file .gif dở, GIỮ mp4 tạm, toast lỗi + nút Retry.
4. App quit giữa lúc convert: mp4 tạm còn trong Caches → menu History không thấy; v1 chấp nhận mất, dọn Caches >7 ngày lúc launch.
5. Màu alpha: GIF 1-bit transparency — nền screenshot luôn đục nên không vấn đề; nếu có background tool bo góc → flatten lên nền trắng trước.

## 7. Test plan
- [ ] Quay GIF 10s vùng 800px → mở bằng Preview/Chrome, lặp vô hạn, tốc độ đúng (đo 10s thật).
- [ ] Export GIF từ video 60fps → GIF 12fps mượt, không giật tua.
- [ ] Video 4K fullscreen → GIF 800px: RAM process < 300MB trong lúc convert (kiểm bằng Activity Monitor — xác nhận streaming hoạt động).
- [ ] Ước tính dung lượng lệch < 2x thực tế.
- [ ] Convert fail giả lập (chmod thư mục đích) → không crash, mp4 tạm còn.

## 8. Unresolved questions
1. Có cần tuỳ chọn "loop N lần" không hay luôn vô hạn? (đề xuất: luôn vô hạn)
2. Chất lượng palette v1 (ImageIO) có đủ với anh không, hay ưu tiên tích hợp gifski sớm?
