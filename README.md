# VKey

Bộ gõ tiếng Việt native cho macOS, Telex/VNI, Unicode, hoàn toàn offline.
Bản thử nghiệm 0.2.0 cho Apple Silicon, macOS 13 trở lên; mới build/chạy trên macOS 27.0.1.

## Cài từ DMG

1. Mở `dist/VKey-0.2.0-arm64.dmg`.
2. Kéo **VKey.app** từ DMG vào **Applications**.
3. Mở **VKey.app** một lần từ Applications. VKey sẽ tự copy và đăng ký phần input method ở vị trí macOS yêu cầu, rồi báo bước tiếp theo. Không cần tự mở `~/Library/Input Methods`.
4. Đăng xuất tài khoản macOS rồi đăng nhập lại để macOS cập nhật danh sách nguồn nhập.
5. Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → **+** → Tiếng Việt → **VKey** → Thêm. Chọn VKey trong menu nguồn nhập của macOS. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy.
6. Menu nguồn nhập của macOS chỉ dùng để chọn **ABC/VKey**. Bấm nút **VK** trên thanh menu để mở các lệnh **Tiếng Việt/English**, **Telex/VNI**, **Hướng dẫn / Giới thiệu** và **Gỡ cài đặt VKey**. macOS tự khởi chạy bộ gõ khi chọn nguồn nhập, không cần thêm mục đăng nhập.

Bản DMG 0.2.0 build 6 đã ký bằng Developer ID Application, bật hardened runtime và đã được Apple notarize/staple. Nếu macOS vẫn chặn trên một máy cụ thể, không tắt Gatekeeper/SIP hay xoá quarantine để vượt chặn; hãy kiểm tra lại checksum và trạng thái macOS.

## Gõ thử

| Telex | VNI | Kết quả |
| --- | --- | --- |
| tieengs Vieetj | tie6ng1 Vie6t5 | tiếng Việt |
| dduwowngf | d9uo7ng2 | đường |
| Nguyeenx | Nguye6n4 | Nguyễn |
| Duowng | Duo7ng | Dương |
| Huwng | Hu7ng | Hưng |

Backspace trong từ đang soạn hoàn tác một phím gõ. Escape trả lại từ gốc chưa chuyển dấu. Space/Enter/Tab/dấu câu kết thúc từ. Cmd/Ctrl/Option và phím di chuyển được chuyển cho ứng dụng sau khi kết thúc từ. Dùng English khi gõ tiếng Anh; không có đoán ngôn ngữ/từ điển. Không sửa dấu từ đã kết thúc.

## Trạng thái

Bản 0.2 thay engine tự viết bằng phần engine của XKey, bỏ mạng/log/dictionary service. 81 ca kiểm tra riêng đã qua; 400/401 ca chuyển dấu lấy từ corpus XKey đạt kết quả mong đợi (ca `qusy` còn giữ nguyên, dùng `quys` để ra “quý”).

Đã gõ từng phím Telex/VNI trong Chrome và VNI trong TextEdit với engine mới. Chrome: đã kiểm tra Backspace, Escape, chuyển ABC/VKey và ô password local bằng chuỗi giả. Khi vừa thay binary/khởi động lạnh, đã ghi nhận vài phím đi qua trước khi phiên nhập sẵn sàng; nên chờ nguồn nhập ổn định rồi gõ. Chưa chứng nhận tương thích mọi ứng dụng, mọi shortcut hay gõ tốc độ cao.

Không phải bản XKey đầy đủ: không có từ điển, tự khôi phục tiếng Anh, macro, cập nhật, dịch thuật, đồng bộ, event tap hoặc xử lý riêng cho từng ứng dụng. Phần host dùng InputMethodKit, nên không hứa hành vi giống hoàn toàn bản XKey dùng event tap.

Xem SECURITY.md, DEPENDENCIES.md, BUILD.md và [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Mã nguồn tương ứng, script build và các license được công khai trong repository; DMG chứa ứng dụng, hướng dẫn ngắn và shortcut Applications.

## Nguồn gốc & Lời cảm ơn

VKey là một bộ gõ độc lập, được phát triển trên nền tảng [XKey](https://github.com/xmannv/xkey) và tiếp nối các đóng góp của cộng đồng mã nguồn mở. Đây là một bản phát hành riêng của VKey, không đại diện cho XKey hoặc [OpenKey](https://github.com/tuyenvm/OpenKey), và hiện không có thông tin về sự liên kết hay xác nhận chính thức từ các tác giả upstream.

Engine offline trong `Sources/XKeyEngine` là một subset đã chỉnh sửa của XKey. Theo các ghi chú trong source của XKey, engine này là bản port Swift dựa trên engine C++ của OpenKey; vì vậy mối liên hệ nguồn gốc với OpenKey được ghi nhận riêng để phản ánh đầy đủ lịch sử phát triển. XKey được công bố dưới MIT License; các phần có nguồn gốc OpenKey được giữ theo GPL-3.0. Chi tiết copyright, license và thay đổi nằm trong [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) và `Resources/Licenses/`.

Phần VKey tích hợp và các thay đổi của project được phát hành theo GPL-3.0. Đây là project cộng đồng miễn phí; việc không thu phí không thay thế các điều kiện license khi phân phối.

## Mục đích dự án

Dự án được phát triển với mục đích học tập, nghiên cứu và đóng góp cho cộng đồng bộ gõ tiếng Việt trên macOS.

Dự án được phát hành dưới dạng mã nguồn mở, với mong muốn ghi nhận phù hợp đóng góp của các dự án upstream và phân biệt rõ phần tích hợp, chỉnh sửa của VKey.
