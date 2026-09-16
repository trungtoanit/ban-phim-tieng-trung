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
- Hội thoại AI theo tình huống bạn tự gõ (OpenAI), mỗi tình huống nói đủ 50 câu thì tự xoá, với chữ Hán + pinyin, góp ý và câu sửa tự nhiên hơn
- Giọng đọc tự nhiên (OpenAI / Google / giọng Nâng cao của iOS)

## Chạy dự án

1. Mở `Ban Phim Tieng Trung.xcodeproj` bằng Xcode 15+.
2. Tạo cấu hình ký riêng cho máy của bạn (file này đã gitignore, không commit):

   ```bash
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

   Điền `DEVELOPMENT_TEAM` (Team ID Apple của bạn) và `APP_GROUP_ID` (tên App Group riêng, ví dụ
   `group.com.tenban.banphimtrung`). Nếu Xcode báo Bundle ID mặc định "is not available" thì điền thêm
   `BUNDLE_ID_BASE` và sửa Bundle ID trong OAuth client iOS trên Google Cloud Console cho khớp.
   **Không** chọn Team hay sửa Bundle ID / App Group trong giao diện Xcode: Xcode sẽ ghi vào
   `project.pbxproj` và làm bẩn repo chung. Giá trị mặc định nằm ở `Config/Shared.xcconfig`.
3. Chạy trên iPhone thật, rồi bật bàn phím: Cài đặt → Cài đặt chung → Bàn phím → Thêm bàn phím mới → **Bàn Phím Trung**, bật **Cho phép truy cập đầy đủ**.
4. Đăng nhập Google: app dùng OAuth client iOS khai ở `GOOGLE_IOS_CLIENT_ID` trong `Config/Shared.xcconfig`; server cũng phải có cùng giá trị ở `GOOGLE_IOS_CLIENT_ID` trong `.env`.

## Lưu ý

- iOS không cho bàn phím dùng micro trực tiếp, nên app chính giữ micro ở chế độ nền và bàn phím gửi lệnh qua App Group.
- Dịch và giọng Google dùng endpoint không chính thức; hội thoại AI tính phí theo tài khoản OpenAI của người dùng.
- Dữ liệu câu, âm Hán Việt, gợi ý trả lời được tạo bằng AI và chưa được người rà soát toàn bộ.
