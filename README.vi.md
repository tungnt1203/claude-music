# claude-music 🎵

[English](README.md)

Nghe nhạc nền ngay trong [Claude Code](https://claude.com/claude-code). Bạn bảo Claude mở bài nào thì nhạc phát từ YouTube ở chế độ nền, bạn cứ làm việc bình thường. Không biết nghe gì thì để Claude tự chọn theo mood.

```
> /music Nơi này có anh
▶ NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP

> /music
Debug lâu rồi, mình bật lo-fi cho bạn tập trung nhé.
▶ lofi hip hop radio 📚 beats to relax/study to

> qua bài khác đi, nhỏ tiếng chút
⏭ ...
🔊 40
```

Không cần API key hay tài khoản. Chỉ phát tiếng, không mở tab trình duyệt.

## Yêu cầu

- macOS hoặc Linux (Windows thì dùng WSL)
- [`mpv`](https://mpv.io) và [`yt-dlp`](https://github.com/yt-dlp/yt-dlp). **Lần đầu phát nhạc, hai tool này được cài tự động.** Claude sẽ tự chạy `music.sh install`:
  - **macOS**: `brew install mpv yt-dlp` (cần có [Homebrew](https://brew.sh))
  - **Linux**: yt-dlp được tải bản chạy sẵn mới nhất vào `~/.local/bin`, không cần quyền root. mpv được cài qua trình quản lý gói (apt, dnf, pacman, zypper hoặc apk). Nếu sudo đòi mật khẩu, Claude sẽ đưa bạn đúng một lệnh để tự chạy bằng `! sudo …`

Trên Linux, script cần `socat` hoặc `python3` để giao tiếp với mpv. Đa số máy đã có sẵn một trong hai.

## Cài đặt

**Cài dạng plugin Claude Code**

```
/plugin marketplace add tungnt1203/claude-music
/plugin install claude-music@claude-music
```

Skill trong plugin có namespace, nên lệnh sẽ là `/claude-music:music`. Bạn cũng có thể nói thẳng, ví dụ "mở nhạc jazz đi".

**Cài dạng skill cá nhân** (để có lệnh ngắn `/music`)

```bash
git clone https://github.com/tungnt1203/claude-music
cp -r claude-music/skills/music ~/.claude/skills/music
```

Cài xong thì khởi động lại Claude Code.

## Cách dùng

| Lệnh | Tác dụng |
|---|---|
| `/music <tên bài hoặc URL>` | Phát ngay (thay bài đang phát) |
| `/music` | Claude tự chọn nhạc theo mood và việc bạn đang làm |
| `/music add <tên bài>` | Thêm vào hàng đợi |
| `/music pause` | Tạm dừng / phát tiếp |
| `/music next` | Qua bài kế |
| `/music vol 40` | Chỉnh âm lượng (0–100) |
| `/music now` | Xem đang phát bài gì |
| `/music stop` | Tắt nhạc |

Nói tự nhiên cũng được: *"bật gì đó chill chill"*, *"nhỏ tiếng chút"*, *"bài này tên gì?"*, *"tắt nhạc"*.

Nếu không muốn lần nào cũng bị hỏi quyền, thêm vào `~/.claude/settings.json`:

```json
{ "permissions": { "allow": ["Bash(*/skills/music/scripts/music.sh:*)"] } }
```

## Cách hoạt động

`scripts/music.sh` chạy `mpv --no-video` với nguồn `ytdl://ytsearch1:<query>`, yt-dlp sẽ lấy kết quả YouTube đầu tiên. Sau đó script điều khiển mpv qua [JSON IPC socket](https://mpv.io/manual/master/#json-ipc). Script là bash thuần nên chạy được cả khi không có Claude:

```bash
skills/music/scripts/music.sh play "đi về nhà đen vâu"
skills/music/scripts/music.sh doctor
```

Biến môi trường `CLAUDE_MUSIC_SOCKET` dùng để đổi đường dẫn socket.

## Xử lý lỗi

- **`missing: mpv yt-dlp`**: cài hai tool này (xem phần Yêu cầu).
- **Không phát được hoặc bài không load**: YouTube hay thay đổi, nên update yt-dlp trước (`brew upgrade yt-dlp` hoặc `pipx upgrade yt-dlp`). Thông báo lỗi có kèm đường dẫn tới log của mpv.
- **Không có tiếng**: thử chạy `mpv "ytdl://ytsearch1:test"` trong terminal thường xem có phát không.

## License

MIT
