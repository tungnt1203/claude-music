# claude-music 🎵

[English](README.md)

Nghe nhạc trong lúc code với [Claude Code](https://claude.com/claude-code). Nhạc phát từ YouTube ở chế độ nền. Không cần tài khoản, không cần API key.

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP
```

## Cài đặt

```
/plugin marketplace add tungnt1203/claude-music
/plugin install claude-music@claude-music
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

Khi cài dạng plugin, tên lệnh đầy đủ là `/claude-music:music`. Cũng có thể nói tự nhiên: *"bật nhạc lo-fi đi"*, *"tắt nhạc"*.

Muốn dùng lệnh ngắn `/music`? Cài dạng skill cá nhân:

```bash
git clone https://github.com/tungnt1203/claude-music
cp -r claude-music/skills/music ~/.claude/skills/
```

## Hỏi đáp

**Có tải nhạc về máy không?** Không. Nhạc chỉ stream qua RAM, không lưu file nào xuống ổ cứng.

**Bài không phát được?** YouTube hay thay đổi, nên update yt-dlp: `brew upgrade yt-dlp`, hoặc chạy lại `music.sh install`.

## License

MIT
