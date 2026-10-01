![cmusic](assets/logo.png)

# cmusic

[English](README.md)

Nghe nhạc trong lúc code với [Claude Code](https://claude.com/claude-code). Nhạc phát từ YouTube ở chế độ nền. Không cần tài khoản, không cần API key.

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP
```

## Cài đặt

```
/plugin marketplace add tungnt1203/cmusic
/plugin install cmusic@cmusic
```

Khởi động lại Claude Code. Lần đầu phát nhạc, Claude sẽ tự cài `mpv` và `yt-dlp`.

Chạy được trên macOS và Linux (Windows thì dùng WSL).

## Cách dùng

| Lệnh | |
|---|---|
| `/music <tên bài>` | Phát bài, hoặc dán link YouTube / SoundCloud |
| `/music` | Để Claude tự chọn theo mood |
| `/music add <tên bài>` | Thêm vào hàng đợi |
| `/music pause` · `next` · `stop` | Điều khiển phát nhạc |
| `/music vol 40` | Chỉnh âm lượng |
| `/music now` | Xem đang phát bài gì |

Khi cài dạng plugin, tên lệnh đầy đủ là `/cmusic:music`. Cũng có thể nói tự nhiên: *"bật nhạc lo-fi đi"*, *"tắt nhạc"*.

Muốn dùng lệnh ngắn `/music`? Cài dạng skill cá nhân:

```bash
git clone https://github.com/tungnt1203/cmusic
cp -r cmusic/skills/music ~/.claude/skills/
```

## Plugin chạy những gì

Mọi thứ chạy trên máy bạn, thông qua một script shell duy nhất là [`skills/music/scripts/music.sh`](skills/music/scripts/music.sh).

- **Phát nhạc**: [`mpv`](https://mpv.io) stream tiếng từ YouTube, hoặc từ link bạn dán, thông qua [`yt-dlp`](https://github.com/yt-dlp/yt-dlp). Script điều khiển mpv qua một socket nằm trong thư mục tạm trên máy.
- **Cài đặt** (chỉ khi máy còn thiếu tool, và chỉ khi Claude chạy `music.sh install`):
  - macOS: `brew install mpv yt-dlp`
  - Linux: `pipx install yt-dlp` nếu máy có pipx, còn mpv (và yt-dlp nếu không có pipx) thì cài bằng trình quản lý gói (apt, dnf, pacman, zypper hoặc apk) qua `sudo`
- **Kết nối mạng**: chỉ tới YouTube hoặc link bạn đưa, và tới nguồn cài gói (Homebrew, PyPI, mirror của distro) khi cài đặt. Không thu thập dữ liệu sử dụng, không gửi dữ liệu đi đâu khác.

Cần chạy Claude Code trên macOS hoặc Linux. Plugin không dùng được trên claude.ai hay app điện thoại, vì ở đó không phát được tiếng ra máy tính của bạn.

## Hỏi đáp

**Có tải nhạc về máy không?** Không. Nhạc chỉ stream qua RAM, không lưu file nào xuống ổ cứng.

**Bài không phát được?** YouTube hay thay đổi, nên update yt-dlp: `brew upgrade yt-dlp` (macOS) hoặc `pipx upgrade yt-dlp` (Linux).

## License

MIT. Đây là dự án cộng đồng, không liên kết với Anthropic.
