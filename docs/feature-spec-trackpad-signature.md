# Feature Spec — Chữ ký bằng Trackpad (Sign)

> Trạng thái: SPEC — chưa implement. Ước lượng: 4-5 ngày.
> Giống tính năng Sign của Preview.app: vẽ chữ ký bằng ngón tay TRÊN TRACKPAD (không phải kéo con trỏ), lưu thư viện chữ ký, chèn vào ảnh như một annotation resize được.

## 1. Mục tiêu & phạm vi

- Vẽ chữ ký bằng trackpad (ngón tay chạm trực tiếp lên trackpad — cách của Preview) HOẶC bằng chuột (fallback).
- Thư viện chữ ký: lưu nhiều chữ ký, dùng lại nhiều lần, xoá được.
- Chèn vào editor như annotation layer: kéo vị trí, resize bằng handle, xoá, undo — và lưu được vào `.cleanshotz`.
- NGOÀI phạm vi v1: ký bằng iPhone camera (như Preview), ký typed-text.

## 2. Kỹ thuật lõi: bắt ngón tay trên trackpad bằng NSTouch

API public, không cần quyền gì thêm:

```swift
final class SignatureCaptureView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]   // nhận touch từ trackpad
        wantsRestingTouches = false
    }
    override func touchesBegan(with event: NSEvent) {
        // event.touches(matching: .began, in: self) → NSTouch
        // touch.normalizedPosition: (0,0) góc dưới-trái → (1,1) góc trên-phải TRACKPAD
    }
    override func touchesMoved(with event: NSEvent) { /* append điểm */ }
    override func touchesEnded(with event: NSEvent) { /* kết thúc stroke */ }
}
```

- **Map toạ độ**: `normalizedPosition` của trackpad → canvas: `x = n.x * canvasW`, `y = (1 - n.y) * canvasH` (flip vì canvas top-left). Trackpad tỉ lệ ~1.6:1, canvas vẽ nên cùng tỉ lệ để nét không méo.
- **Chỉ nhận 1 ngón**: track theo `NSTouch.identity`; ngón thứ 2 chạm → bỏ qua (tránh nét rác khi tựa tay). Nhấc ngón >600ms → coi như stroke mới (chữ ký nhiều nét: dấu, chấm i...).
- **Làm mượt**: tái dùng midpoint quad-curve của pencil (annotation-renderer strokePath) + lọc điểm quá gần (< 1.5px) để giảm noise.
- **Độ dày nét theo tốc độ** (đẹp như bút thật): width = clamp(base * (1.2 - speedNormalized), 0.4*base, 1.4*base) — tính per-segment, vẽ bằng các đoạn variable-width (v1 đơn giản: 1 width cố định, biến thiên là P2).
- **Mouse fallback**: cùng view, mouseDown/Dragged/Up ghi điểm theo toạ độ chuột (cho ai không có trackpad/thích vẽ bằng chuột).

## 3. Data model

### 3.1 Signature (thư viện)
```swift
struct StoredSignature: Codable, Identifiable {
    let id: UUID
    var strokes: [[CGPoint]]   // toạ độ CHUẨN HOÁ 0..1 theo bounding box của chữ ký
    var aspectRatio: CGFloat   // width/height của bounding box gốc
    var createdAt: Date
}
```
- File: `~/Library/Application Support/CleanShotZ/signatures.json` — store mới `signature-library-store.swift` (load/save/delete, max 10 chữ ký).
- **Bảo mật**: chữ ký là dữ liệu nhạy cảm. v1 lưu file thường + ghi chú trong docs; P2: chuyển sang Keychain (như Preview) — flag migration sẵn trong store.

### 3.2 Annotation mới
```swift
// annotation-model.swift
case signature(strokes: [[CGPoint]], rect: CGRect)
// strokes chuẩn hoá 0..1; rect = vị trí + kích thước đặt trên ảnh (pixel ảnh gốc)
```
- `boundingRect` = rect (+ inset tolerance); `translate` = offset rect; `handles` = 4 góc (như rect); `moveHandle` = resize rect **giữ tỉ lệ** (aspect lock mặc định — chữ ký không được méo; giữ Shift để tự do).
- Renderer: scale từng stroke: `point = rect.origin + normalized * rect.size`; vẽ strokePath màu style.color (default đen), lineWidth = style.lineWidth * rect.height/150 (nét to theo kích thước đặt).
- Hit-test: `containsPoint` dùng bounding rect (chữ ký mảnh, hit theo nét sẽ khó click — dùng rect cho dễ chọn).
- **Codec `.cleanshotz`**: AnnotationDTO thêm kind `"signature"`, field `strokeGroups: [[CGPoint]]?` + dùng lại `rect` — backward compatible (file cũ không có kind này; app cũ đọc file mới sẽ skip qua `compactMap` hiện có ✓).

## 4. UX

### 4.1 Toolbar editor
- Thêm tool `signature` (icon `signature` SF Symbol) vào cột tool, shortcut `g`.
- Chọn tool → **popover thư viện** neo vào nút:
  - Danh sách chữ ký đã lưu (render thumbnail 120x50, nền trắng viền), click chọn → con trỏ thành stamp mode.
  - Nút `+ Add Signature…` → mở sheet capture.
  - Hover mỗi chữ ký có nút 🗑 xoá (confirm).
- Stamp mode: click lên canvas → đặt chữ ký tại điểm click, kích thước mặc định = 25% chiều rộng ảnh (giữ aspect), auto-select với handle → kéo/resize ngay.

### 4.2 Sheet capture chữ ký
- Sheet 560×320 trên editor window: canvas trắng lớn (tỉ lệ trackpad), đường baseline mờ ngang 60% chiều cao (như Preview).
- Hướng dẫn trên canvas khi trống: "Ký bằng ngón tay trên trackpad, hoặc vẽ bằng chuột".
- Nút: `Clear` (xoá vẽ lại), `Cancel`, `Done` (disabled khi chưa có nét).
- Done → chuẩn hoá strokes theo bounding box (trim lề trống) → lưu vào library → đóng sheet → tự chọn chữ ký vừa tạo trong popover.
- Esc = Cancel. Trong lúc sheet mở, tool shortcut của canvas không ăn (sheet là first responder — pattern đã có với text editing).

## 5. Files mới
| File | Trách nhiệm |
|---|---|
| `signature-model.swift` | StoredSignature + normalize/trim helpers |
| `signature-library-store.swift` | load/save/delete signatures.json |
| `signature-capture-view.swift` | NSView bắt NSTouch + mouse, smoothing |
| `signature-capture-sheet.swift` | SwiftUI sheet wrap capture view + nút |
| `signature-picker-popover.swift` | Thư viện + Add/Delete |
| (sửa) annotation-model / renderer / hit-testing / canvas mouse-handling / project-file-codec / editor-root-view | case .signature + tool mới |

## 6. Edge cases
1. Máy không có trackpad (Mac mini + chuột thường): sheet vẫn hoạt động bằng chuột; text hướng dẫn đổi theo `NSEvent` có touch capability không kiểm được trực tiếp → luôn ghi cả 2 cách.
2. Palm rejection: chỉ nhận touch đầu tiên (identity match) — ngón 2+ bị bỏ.
3. Chữ ký 1 chấm (touch không move): bỏ nét < 3 điểm khi Done; nếu tổng chỉ có nét rác → Done vẫn disabled.
4. Resize chữ ký về quá nhỏ: min rect 40px width (pattern min-size của All-in-One resize).
5. Undo: đặt chữ ký = 1 undo point (registerUndoPoint trước khi add — pattern counter).
6. Style controls: khi chọn signature annotation → chỉ hiện color swatch + lineWidth (ẩn fill/font) — thêm case vào `showsShapeControls`/`showsTextControls` logic.

## 7. Test plan
- [ ] Vẽ chữ ký bằng trackpad → nét mượt, đúng hướng (không bị lộn ngược y).
- [ ] 3 nét rời (ký + gạch ngang + chấm) → giữ đủ 3 nét.
- [ ] Lưu 2 chữ ký, quit app, mở lại → còn nguyên.
- [ ] Đặt lên ảnh, resize handle → giữ tỉ lệ, không méo.
- [ ] Save `.cleanshotz` có chữ ký → mở lại → chữ ký đúng vị trí, vẫn sửa được.
- [ ] Export PNG → chữ ký nét ở đúng độ phân giải (không alias nặng).
- [ ] Máy chỉ có chuột → vẫn ký được.

## 8. Unresolved questions
1. Chữ ký lưu Keychain ngay từ v1 hay file JSON trước (đề xuất: JSON trước, Keychain P2)?
2. Có cần độ dày nét theo lực nhấn Force Touch không (`NSEvent.pressure`) hay theo tốc độ là đủ?
