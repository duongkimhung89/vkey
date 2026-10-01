# VKey

Bộ gõ tiếng Việt native cho macOS, Telex/VNI, Unicode, hoàn toàn offline.
Cho Apple Silicon, macOS 13 trở lên; mới build/chạy trên macOS 27.0.1.
Bản mới nhất là 0.3.7, có DMG trên GitHub Releases và cài được qua Homebrew (`brew install --cask duongkimhung89/vkey/vkey`).

## Cài từ DMG

1. Tải bản mới nhất [`VKey-0.3.7-arm64.dmg`](https://github.com/duongkimhung89/vkey/releases/latest) từ GitHub Releases rồi mở file DMG.
2. Kéo **VKey.app** từ DMG vào **Applications**.
3. Mở **VKey.app** một lần từ Applications. VKey sẽ tự copy và đăng ký phần input method ở vị trí macOS yêu cầu, rồi báo bước tiếp theo. Không cần tự mở `~/Library/Input Methods`.
4. Đăng xuất tài khoản macOS rồi đăng nhập lại để macOS cập nhật danh sách nguồn nhập.
5. Cài đặt hệ thống → Bàn phím → Nhập văn bản → Sửa → **+** → Tiếng Việt → **VKey** → Thêm. Chọn VKey trong menu nguồn nhập của macOS. Nếu VKey vẫn chưa xuất hiện, hãy khởi động lại máy.
6. Menu nguồn nhập của macOS chỉ dùng để chọn **ABC/VKey**. Nút **VI/EN** trên thanh menu mở các lệnh **Tiếng Việt/English**, **Telex/VNI**, **Hướng dẫn**, **Giới thiệu** (kèm số phiên bản đang chạy) và **Gỡ cài đặt VKey**; **Control + Shift** đổi nhanh Việt/Anh. macOS tự khởi chạy bộ gõ khi chọn nguồn nhập, không cần thêm mục đăng nhập.

Từ 0.3.0, cập nhật không cần đăng xuất: mở bản VKey.app mới một lần, nó tự thay bản trong `~/Library/Input Methods` và khởi động lại bộ gõ đang chạy. Khi build từ source, `./scripts/dev-install.sh` làm cả ba việc build, test, cài.

Bản 0.3.7 đã ký bằng Developer ID Application, bật hardened runtime và được Apple notarize/staple; bản 0.3.0 chưa được notarize. Nếu macOS vẫn chặn trên một máy cụ thể, không tắt Gatekeeper/SIP hay xoá quarantine để vượt chặn; hãy kiểm tra lại checksum và trạng thái macOS.

## Gõ thử

| Telex | VNI | Kết quả |
| --- | --- | --- |
| tieengs Vieetj | tie6ng1 Vie6t5 | tiếng Việt |
| dduwowngf | d9uo7ng2 | đường |
| Nguyeenx | Nguye6n4 | Nguyễn |
| Duowng | Duo7ng | Dương |
| Huwng | Hu7ng | Hưng |

Backspace xoá một ký tự của từ đang gõ (`tiếng` → `tiến`) và gõ tiếp được trên phần còn lại. Escape trả lại các phím đã gõ; khi không có gì để trả lại, Escape thuộc về ứng dụng. Space/Enter/Tab/dấu câu kết thúc từ; trong Telex, `[` và `]` cũng là dấu câu (không phải phím tắt cho `ơ`, `ư`). Đổi Việt/Anh hay Telex/VNI giữa chừng kết thúc từ giống như gõ Space. Cmd/Ctrl/Option và phím di chuyển được chuyển cho ứng dụng sau khi kết thúc từ. Không sửa dấu từ đã kết thúc.

### Gõ xen tiếng Anh

VKey áp dụng một quy tắc cấu trúc khi từ kết thúc: nếu dấu rơi vào vị trí không hợp lệ trong tiếng Việt, VKey trả lại đúng các phím đã gõ. Luật này không dùng từ điển và không có ngoại lệ viết tay.

| Gõ | Ra | Vì sao |
| --- | --- | --- |
| `windows`, `user`, `software`, `expect`, `google` | giữ nguyên | `ưindows`, `uẻ`, `sờtware`… không thể là âm tiết tiếng Việt |
| `ddc`, `ddk`, `VNDD`, `ddiiii` | `đc`, `đk`, `VNĐ`, `điiii` | viết tắt và kéo dài chữ được giữ |
| `tesst`, `thiss`, `passs` | `test`, `this`, `pass` | gõ lặp phím dấu để huỷ dấu, như Telex chuẩn |
| `test`, `this`, `is`, `more`, `taxi`, `down` | `tét`, `thí`, `í`, `moẻ`, `tãi`, `dơn` | đúng dạng âm tiết tiếng Việt nên không có gì cho thấy bạn định gõ tiếng Anh; chuyển sang English hoặc gõ lặp phím dấu |
| `pass`, `off`, `error`, `password` | `pas`, `of`, `eror`, `pasword` | phím dấu lặp là phím huỷ của Telex; gõ thêm một lần nữa (`passs`) để ra đúng chữ |

Trong 1.211 từ tiếng Anh thông dụng của bộ test, 1.081 từ ra đúng như gõ, 40 từ chứa chữ đôi (`ss`, `ff`, `rr`) cần gõ chữ đó ba lần, còn lại là từ có dạng âm tiết tiếng Việt. Luật này luôn bật, nên từ mượn bỏ dấu ngoài quy tắc tiếng Việt (như `micrô`) hiện chưa gõ được dấu. Một số cụm phụ âm ngoài phạm vi quy tắc hiện tại, như `cr` và `bl`, chưa được hỗ trợ; vì vậy `crôm` hiện chưa chuyển đổi.

Trong VNI, chữ số đứng sau nguyên âm vẫn là phím dấu (`a1` → `á`), nên `U23`, `A4` cần chuyển sang English.

## Cách VKey đưa chữ vào ứng dụng

Từ đang gõ là văn bản thường, không gạch chân. Phím nào chỉ thêm chính chữ của nó thì để ứng dụng tự gõ, giống hệt khi không có bộ gõ; VKey chỉ can thiệp khi một phím làm đổi chữ đã có (thêm dấu, mũ), và chỉ thay đúng phần đổi. Khi ứng dụng không báo vị trí con trỏ, không di chuyển con trỏ theo chữ gõ hoặc bỏ qua vùng thay thế, VKey dùng marked text tiêu chuẩn của InputMethodKit với gạch chân rất mờ. VKey chỉ ghi nhớ bundle identifier của ứng dụng cần cơ chế dự phòng.

Trình duyệt và app Electron giữ văn bản ở tiến trình khác nên khi gõ nhanh, vị trí con trỏ chúng báo về có thể chậm vài phím. VKey tự ghi lại các vị trí con trỏ đã đi qua sau mỗi phím; vị trí báo về trùng một trong số đó chỉ là báo chậm, từ đang gõ vẫn giữ nguyên và dấu vẫn được bỏ đúng. Chỉ khi con trỏ nằm ở chỗ khác (bấm chuột, chọn vùng) thì từ mới kết thúc.

Giới hạn đã biết: ở ứng dụng không báo cú bấm chuột cho bộ gõ, nếu bấm vào giữa chính từ đang gõ rồi gõ ngay một phím dấu, VKey có thể coi như con trỏ vẫn ở cuối từ. Với ứng dụng bỏ qua vùng thay thế, lần đổi dấu đầu tiên chèn sai một từ; từ đó VKey nhớ ứng dụng này và dùng marked text.

## Trạng thái

`./scripts/test.sh` (chạy không cần giao diện):

- 81 ca chuyển dấu riêng và 400/401 ca trong bộ kiểm thử chuyển đổi tham chiếu (ca `qusy` còn giữ nguyên, dùng `quys` để ra “quý”).
- 817 từ của một đoạn văn tiếng Việt gõ theo 4 cách (Telex/VNI, dấu cuối từ hoặc ngay sau nguyên âm).
- 7.672/7.884 âm tiết của từ điển ibus-bamboo (dùng làm dữ liệu test, không đi kèm app) gõ được cả bốn cách. Phần còn lại là tiền tố phụ âm lạ (`crô`, `blô`), phiên âm và vài mục sai chính tả trong chính từ điển.
- Bộ từ tiếng Anh thông dụng (xem trên).
- Gõ nhanh vào ô văn bản giả báo vị trí con trỏ chậm ngẫu nhiên 0–4 phím (cả đoạn văn 817 từ, bốn cách gõ, có Backspace): văn bản ra phải giống hệt ô không chậm.
- Mô phỏng phiên gõ trên ô văn bản giả: câu xen Anh–Việt, Backspace, Escape, phím tắt, chọn vùng rồi xoá, bấm chuột giữa từ, thanh địa chỉ có gợi ý tự điền, ứng dụng không hỗ trợ thay thế trực tiếp.

`./scripts/live-test.sh` gõ bằng phím hệ thống thật vào NSTextView, NSTextField và WebKit qua bản VKey đang cài. Script cần quyền Accessibility cho `build/VKeyLiveTest.app` (chỉ công cụ test cần, VKey thì không). Lỗi bộ test từng báo không nhận được phím trên macOS 27.0.1 là do chỉ chạy `RunLoop` mà không xử lý hàng đợi sự kiện của AppKit; đã sửa để lấy và chuyển tiếp sự kiện bàn phím. Cách đọc `contenteditable` cũng đã sửa để giữ xuống dòng. Ngày 01/10/2026, 102 ca đều đã đạt qua lần chạy đầy đủ và chạy lại nhóm bị ảnh hưởng; xem [báo cáo live test](reports/LIVE-TEST.md). Bản 0.3.7 được dùng thử khi gõ hằng ngày nhưng chưa được kiểm tra tay có hệ thống trên Safari, Chrome, Terminal, VS Code; các kiểm tra tay của 0.2.0 nằm trong reports/INTEGRATION.md.

VKey tập trung vào bộ gõ tiếng Việt offline native cho macOS với Telex, VNI, Unicode và InputMethodKit. Khả năng tương thích có thể khác nhau tùy ứng dụng; kết quả kiểm thử hiện có được ghi ở trên và trong thư mục `reports/`.

Xem SECURITY.md, DEPENDENCIES.md, BUILD.md và [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Mã nguồn tương ứng, script build và các license được công khai trong repository; DMG chứa ứng dụng, hướng dẫn ngắn và shortcut Applications.

## Nguồn gốc & Lời cảm ơn

VKey là một dự án độc lập. Xin cảm ơn các tác giả và cộng đồng XKey, OpenKey cùng các dự án mã nguồn mở liên quan đã chia sẻ nền tảng kỹ thuật cho dự án. Thông tin về nguồn, tác giả, license và các thay đổi được ghi trong [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) và `Resources/Licenses/`.

Phần VKey tích hợp và các thay đổi của project được phát hành theo GPL-3.0. Đây là project cộng đồng miễn phí; việc không thu phí không thay thế các điều kiện license khi phân phối.

## Mục đích dự án

Dự án được phát triển với mục đích học tập, nghiên cứu và đóng góp cho cộng đồng bộ gõ tiếng Việt trên macOS.

Dự án được phát hành dưới dạng mã nguồn mở, với mong muốn ghi nhận phù hợp các đóng góp và phân biệt rõ phần tích hợp, chỉnh sửa của VKey.
