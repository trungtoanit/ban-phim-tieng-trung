# Bàn Phím Tiếng Trung

Ứng dụng iOS (SwiftUI) giúp người Việt nhắn tin và luyện nói tiếng Trung.

## Tính năng

**Bàn phím (Keyboard Extension)**
- Ghi âm ngay trên bàn phím: nói tiếng Việt → dịch sang tiếng Trung, hoặc nói thẳng tiếng Trung
- Pinyin hiển thị thẳng hàng trên từng từ chữ Hán (tuỳ chọn âm Hán Việt)
- 📋 Hiểu tin nhắn đã copy: pinyin + nghĩa tiếng Việt + gợi ý trả lời nhanh
- Dịch chữ tiếng Việt đã gõ, giọng văn thân mật / lịch sự, chạm vào từ để nghe và xem nghĩa
- Chấm phát âm: tô đỏ từ máy nghe chưa chắc, chọn lại chữ đúng ý

**Ứng dụng**
- Luyện nói 1000 câu giao tiếp theo 20 chủ đề, đọc đúng thì câu được đánh dấu đã thuộc
- Hội thoại AI theo tình huống (OpenAI) với chữ Hán + pinyin, góp ý và câu sửa tự nhiên hơn
- Giọng đọc tự nhiên (OpenAI / Google / giọng Nâng cao của iOS)

## Chạy dự án

1. Mở `Ban Phim Tieng Trung.xcodeproj` bằng Xcode 15+.
2. Chọn **Team** trong *Signing & Capabilities* cho cả 2 target: `Ban Phim Tieng Trung` và `BanPhimTrungKeyboard`.
3. Đảm bảo cả 2 target có App Group `group.hihi.Ban-Phim-Tieng-Trung` (đổi bundle id / App Group nếu cần).
4. Chạy trên iPhone thật, rồi bật bàn phím: Cài đặt → Cài đặt chung → Bàn phím → Thêm bàn phím mới → **Bàn Phím Trung**, bật **Cho phép truy cập đầy đủ**.
5. Hội thoại AI: mở tab **Hội thoại AI** → ⚙︎ → nhập khoá OpenAI của bạn (lưu trong Keychain, không nằm trong mã nguồn).

## Lưu ý

- iOS không cho bàn phím dùng micro trực tiếp, nên app chính giữ micro ở chế độ nền và bàn phím gửi lệnh qua App Group.
- Dịch và giọng Google dùng endpoint không chính thức; hội thoại AI tính phí theo tài khoản OpenAI của người dùng.
- Dữ liệu câu, âm Hán Việt, gợi ý trả lời được tạo bằng AI và chưa được người rà soát toàn bộ.
