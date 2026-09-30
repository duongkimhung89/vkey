# VKey

Bộ gõ tiếng Việt native cho macOS, Telex/VNI, Unicode, hoàn toàn offline.
Cho Apple Silicon, macOS 13 trở lên; mới build/chạy trên macOS 27.0.1.
Bản mới nhất là 0.3.1, có DMG trên GitHub Releases và cài được qua Homebrew (`brew install --cask duongkimhung89/vkey/vkey`).

## Cài từ DMG

1. Tải bản mới nhất [`VKey-0.3.1-arm64.dmg`](https://github.com/duongkimhung89/vkey/releases/latest) từ GitHub Releases rồi mở file DMG.
2. Kéo **VKey.app** từ DMG vào **Applications**.
3. Mở **VKey.app** một lần từ Applications. VKey sẽ tự copy và đăng ký phần input method ở vị trí macOS yêu cầu, rồi báo bước tiếp theo. Không cần tự mở `~/Library/Input Methods`.
4. Đăng xuất tài khoản macOS rồi đăng nhập lại để macOS cập nhật danh sách nguồn nhập.
5. Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → **+** → Tiếng Việt → **VKey** → Thêm. Chọn VKey trong menu nguồn nhập của macOS. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy.
6. Menu nguồn nhập của macOS chỉ dùng để chọn **ABC/VKey**. Nút **VI/EN** trên thanh menu mở các lệnh **Tiếng Việt/English**, **Telex/VNI**, **Kiểm tra chính tả**, **Hướng dẫn / Giới thiệu** và **Gỡ cài đặt VKey**; **Control + Shift** đổi nhanh Việt/Anh. macOS tự khởi chạy bộ gõ khi chọn nguồn nhập, không cần thêm mục đăng nhập.

Từ 0.3.0, cập nhật không cần đăng xuất: mở bản VKey.app mới một lần, nó tự thay bản trong `~/Library/Input Methods` và khởi động lại bộ gõ đang chạy. Khi build từ source, `./scripts/dev-install.sh` làm cả ba việc build, test, cài.

Các bản 0.3.x đã ký bằng Developer ID Application và bật hardened runtime nhưng **chưa** được Apple notarize; bản 0.2.0 build 6 đã được notarize/staple. Nếu macOS vẫn chặn trên một máy cụ thể, không tắt Gatekeeper/SIP hay xoá quarantine để vượt chặn; hãy kiểm tra lại checksum và trạng thái macOS.

## Gõ thử

| Telex | VNI | Kết quả |
| --- | --- | --- |
| tieengs Vieetj | tie6ng1 Vie6t5 | tiếng Việt |
| dduwowngf | d9uo7ng2 | đường |
| Nguyeenx | Nguye6n4 | Nguyễn |
| Duowng | Duo7ng | Dương |
| Huwng | Hu7ng | Hưng |

Backspace xoá một ký tự của từ đang gõ (`tiếng` → `tiến`) và gõ tiếp được trên phần còn lại. Escape trả lại các phím đã gõ; khi không có gì để trả lại, Escape thuộc về ứng dụng. Space/Enter/Tab/dấu câu kết thúc từ. Cmd/Ctrl/Option và phím di chuyển được chuyển cho ứng dụng sau khi kết thúc từ. Không sửa dấu từ đã kết thúc.

### Gõ xen tiếng Anh

VKey chỉ có một luật, như Unikey/OpenKey: khi từ kết thúc, nếu dấu đã bỏ rơi vào chỗ tiếng Việt không cho phép (vần hoặc thanh không hợp lệ) thì trả lại đúng các phím đã gõ. Luật này không dùng từ điển và không có ngoại lệ viết tay.

| Gõ | Ra | Vì sao |
| --- | --- | --- |
| `windows`, `user`, `software`, `expect`, `google` | giữ nguyên | `ưindows`, `uẻ`, `sờtware`… không thể là âm tiết tiếng Việt |
| `ddc`, `ddk`, `VNDD`, `ddiiii` | `đc`, `đk`, `VNĐ`, `điiii` | viết tắt và kéo dài chữ được giữ |
| `tesst`, `thiss`, `passs` | `test`, `this`, `pass` | gõ lặp phím dấu để huỷ dấu, như Telex chuẩn |
| `test`, `this`, `is`, `more`, `taxi`, `down` | `tét`, `thí`, `í`, `moẻ`, `tãi`, `dơn` | đúng dạng âm tiết tiếng Việt nên không có gì cho thấy bạn định gõ tiếng Anh; chuyển sang English hoặc gõ lặp phím dấu |
| `pass`, `off`, `error`, `password` | `pas`, `of`, `eror`, `pasword` | phím dấu lặp là phím huỷ của Telex; gõ thêm một lần nữa (`passs`) để ra đúng chữ |

Trong 1.211 từ tiếng Anh thông dụng của bộ test, 1.081 từ ra đúng như gõ, 40 từ chứa chữ đôi (`ss`, `ff`, `rr`) cần gõ chữ đó ba lần, còn lại là từ có dạng âm tiết tiếng Việt. Mục **Kiểm tra chính tả** trên menu tắt luật này và cả việc chỉ bỏ dấu đúng chỗ, để bỏ dấu tự do như 0.2 (gõ `micrô`). Tiền tố phụ âm lạ như `cr`, `bl` vẫn do engine XKey xử lý như cũ nên `crôm` chưa gõ được.

Trong VNI, chữ số đứng sau nguyên âm vẫn là phím dấu (`a1` → `á`), nên `U23`, `A4` cần chuyển sang English.

## Cách VKey đưa chữ vào ứng dụng

Từ đang gõ là văn bản thường, không gạch chân. Phím nào chỉ thêm chính chữ của nó thì để ứng dụng tự gõ, giống hệt khi không có bộ gõ; VKey chỉ can thiệp khi một phím làm đổi chữ đã có (thêm dấu, mũ), và chỉ thay đúng phần đổi. Đây là cách làm của chế độ direct trong XKey IMKit. Ứng dụng không báo vị trí con trỏ, không di chuyển con trỏ theo chữ gõ, hoặc bỏ qua vùng thay thế sẽ được chuyển sang marked text chuẩn của InputMethodKit với gạch chân rất mờ; VKey chỉ ghi nhớ bundle identifier của ứng dụng đó.

## Trạng thái

`./scripts/test.sh` (chạy không cần giao diện):

- 81 ca chuyển dấu riêng và 400/401 ca của corpus XKey (ca `qusy` còn giữ nguyên, dùng `quys` để ra “quý”).
- 817 từ của một đoạn văn tiếng Việt gõ theo 4 cách (Telex/VNI, dấu cuối từ hoặc ngay sau nguyên âm).
- 7.672/7.884 âm tiết của từ điển ibus-bamboo (dùng làm dữ liệu test, không đi kèm app) gõ được cả bốn cách. Phần còn lại là tiền tố phụ âm lạ (`crô`, `blô`), phiên âm và vài mục sai chính tả trong chính từ điển.
- Bộ từ tiếng Anh thông dụng (xem trên).
- Mô phỏng phiên gõ trên ô văn bản giả: câu xen Anh–Việt, Backspace, Escape, phím tắt, chọn vùng rồi xoá, bấm chuột giữa từ, thanh địa chỉ có gợi ý tự điền, ứng dụng không hỗ trợ thay thế trực tiếp.

`./scripts/live-test.sh` gõ bằng phím hệ thống thật vào NSTextView, NSTextField và WebKit qua bản VKey đang cài. Script cần quyền Accessibility cho `build/VKeyLiveTest.app` (chỉ công cụ test cần, VKey thì không). Bản 0.3.0 **chưa** được chạy bộ test này và chưa được kiểm tra tay có hệ thống trên Safari, Chrome, Terminal, VS Code; các kiểm tra tay của 0.2.0 nằm trong reports/INTEGRATION.md.

Không phải bản XKey đầy đủ: không có macro, cập nhật, dịch thuật, đồng bộ, event tap hoặc quy tắc riêng cho từng ứng dụng. Phần host dùng InputMethodKit, nên không hứa hành vi giống hoàn toàn bản XKey dùng event tap.

Xem SECURITY.md, DEPENDENCIES.md, BUILD.md và [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Mã nguồn tương ứng, script build và các license được công khai trong repository; DMG chứa ứng dụng, hướng dẫn ngắn và shortcut Applications.

## Nguồn gốc & Lời cảm ơn

VKey là một bộ gõ độc lập, được phát triển trên nền tảng [XKey](https://github.com/xmannv/xkey) và tiếp nối các đóng góp của cộng đồng mã nguồn mở. Đây là một bản phát hành riêng của VKey, không đại diện cho XKey hoặc [OpenKey](https://github.com/tuyenvm/OpenKey), và hiện không có thông tin về sự liên kết hay xác nhận chính thức từ các tác giả upstream.

Engine offline trong `Sources/XKeyEngine` là một subset đã chỉnh sửa của XKey. Theo các ghi chú trong source của XKey, engine này là bản port Swift dựa trên engine C++ của OpenKey; vì vậy mối liên hệ nguồn gốc với OpenKey được ghi nhận riêng để phản ánh đầy đủ lịch sử phát triển. XKey được công bố dưới MIT License; các phần có nguồn gốc OpenKey được giữ theo GPL-3.0. Chi tiết copyright, license và thay đổi nằm trong [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) và `Resources/Licenses/`.

Phần VKey tích hợp và các thay đổi của project được phát hành theo GPL-3.0. Đây là project cộng đồng miễn phí; việc không thu phí không thay thế các điều kiện license khi phân phối.

## Mục đích dự án

Dự án được phát triển với mục đích học tập, nghiên cứu và đóng góp cho cộng đồng bộ gõ tiếng Việt trên macOS.

Dự án được phát hành dưới dạng mã nguồn mở, với mong muốn ghi nhận phù hợp đóng góp của các dự án upstream và phân biệt rõ phần tích hợp, chỉnh sửa của VKey.
