#!/usr/bin/env python3
"""QR Code Decoder GUI - Modern minimal design"""

import sys
import os
import tempfile
import tkinter as tk
from tkinter import filedialog, scrolledtext
from urllib.parse import urlparse, parse_qs, unquote

try:
    from pyzbar.pyzbar import decode
    from PIL import Image, ImageGrab, ImageTk
except ImportError:
    print("Missing: pip install pyzbar Pillow")
    sys.exit(1)

UI_LATIN_FONT = "Segoe UI"
UI_CJK_FONT = "SimSun"
MONO_LATIN_FONT = "Cascadia Code"

def _has_cjk(text):
    return any("\u4e00" <= ch <= "\u9fff" for ch in str(text))


def ui_font(size, *styles, text=""):
    family = UI_CJK_FONT if _has_cjk(text) else UI_LATIN_FONT
    return (family, size, *styles)


def mono_font(size, *styles, text=""):
    family = UI_CJK_FONT if _has_cjk(text) else MONO_LATIN_FONT
    return (family, size, *styles)


# -- Color palette (Catppuccin Mocha) --
C = {
    "bg":       "#1e1e2e",
    "surface":  "#313244",
    "overlay":  "#45475a",
    "text":     "#cdd6f4",
    "subtext":  "#a6adc8",
    "muted":    "#585b70",
    "blue":     "#89b4fa",
    "green":    "#a6e3a1",
    "red":      "#f38ba8",
    "yellow":   "#f9e2af",
    "teal":     "#94e2d5",
    "lavender": "#b4befe",
    "mantle":   "#181825",
    "crust":    "#11111b",
}


def decode_qr(image_path: str) -> list[str]:
    img = Image.open(image_path)
    results = decode(img)
    return [r.data.decode("utf-8") for r in results]


def parse_totp_url(url: str) -> dict | None:
    if not url.startswith("otpauth://"):
        return None
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    account = unquote(parsed.path.lstrip("/totp/"))
    return {
        "account": account,
        "secret": params.get("secret", [""])[0],
        "issuer": params.get("issuer", [""])[0],
    }


class FlatButton(tk.Canvas):
    """Custom flat button with rounded corners, hover, and click flash."""

    def __init__(self, parent, text, command, bg, fg, hover_bg=None,
                 font=None, padx=18, pady=8, status_cb=None, **kw):
        self.command = command
        self.bg = bg
        self.hover_bg = hover_bg or self._adjust(bg, 20)
        self.press_bg = self._adjust(bg, -25)
        self.fg = fg
        self.text = text
        self._hovered = False
        self._status_cb = status_cb
        self.font = font or ui_font(10, text=text)

        # Measure text
        tmp = tk.Label(parent, text=text, font=self.font)
        tw = tmp.winfo_reqwidth()
        th = tmp.winfo_reqheight()
        tmp.destroy()

        w = tw + padx * 2
        h = th + pady * 2
        r = 8

        super().__init__(parent, width=w, height=h, bg=parent["bg"],
                         highlightthickness=0, bd=0, **kw)

        self._r = r
        self._draw(self.bg)

        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<Button-1>", self._on_click)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.config(cursor="hand2")

    def _round_rect(self, x1, y1, x2, y2, r, fill):
        points = [
            x1 + r, y1, x2 - r, y1,
            x2, y1, x2, y1 + r,
            x2, y2 - r, x2, y2,
            x2 - r, y2, x1 + r, y2,
            x1, y2, x1, y2 - r,
            x1, y1 + r, x1, y1,
        ]
        return self.create_polygon(points, smooth=True, fill=fill, outline="")

    def _draw(self, color, text=None):
        self.delete("all")
        w, h = self.winfo_reqwidth(), self.winfo_reqheight()
        self._round_rect(0, 0, w, h, self._r, color)
        self.create_text(w // 2, h // 2, text=text or self.text,
                         fill=self.fg, font=self.font)

    def _adjust(self, hex_color, amount):
        hex_color = hex_color.lstrip("#")
        r, g, b = int(hex_color[:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
        r = max(0, min(255, r + amount))
        g = max(0, min(255, g + amount))
        b = max(0, min(255, b + amount))
        return f"#{r:02x}{g:02x}{b:02x}"

    def _on_enter(self, e):
        self._hovered = True
        self._draw(self.hover_bg)

    def _on_leave(self, e):
        self._hovered = False
        self._draw(self.bg)

    def _on_click(self, e):
        # Press state: darker bg + brief text flash
        self._draw(self.press_bg, text=self.text)

    def _on_release(self, e):
        # Flash back to hover, then fire command
        color = self.hover_bg if self._hovered else self.bg
        self._draw(color)
        if self._status_cb:
            self._status_cb(self.text)
        self.command()


class Card(tk.Frame):
    """A card-like frame with border."""

    def __init__(self, parent, **kw):
        super().__init__(parent, bg=C["surface"],
                         highlightbackground=C["muted"],
                         highlightthickness=1, **kw)


class App:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("QR Decode")
        self.root.geometry("480x580")
        self.root.resizable(False, False)
        self.root.configure(bg=C["bg"])

        # Icon
        try:
            self.root.iconbitmap(default="")
        except Exception:
            pass

        self._build()
        self._bind()

    # -- UI Construction --

    def _build(self):
        # Header
        header = tk.Frame(self.root, bg=C["bg"])
        header.pack(fill="x", padx=20, pady=(18, 4))

        tk.Label(header, text="QR Decode", font=ui_font(16, "bold", text="QR Decode"),
                 bg=C["bg"], fg=C["text"]).pack(side="left")

        tk.Label(header, text="v1.0", font=ui_font(9, text="v1.0"),
                 bg=C["bg"], fg=C["muted"]).pack(side="left", padx=(6, 0), pady=(4, 0))

        # -- Collapsible help --
        self._help_open = False

        self.help_toggle = tk.Frame(self.root, bg=C["surface"],
                                     highlightbackground=C["muted"],
                                     highlightthickness=1)
        self.help_toggle.pack(fill="x", padx=20, pady=(8, 0))

        self.help_arrow = tk.Label(
            self.help_toggle, text="[+]", font=mono_font(10, text="[+]"),
            bg=C["surface"], fg=C["muted"], padx=8
        )
        self.help_arrow.pack(side="left", pady=6)

        self.help_title = tk.Label(
            self.help_toggle, text="What does this do?", font=ui_font(10, text="What does this do?"),
            bg=C["surface"], fg=C["subtext"]
        )
        self.help_title.pack(side="left", pady=6)

        for w in (self.help_toggle, self.help_arrow, self.help_title):
            w.bind("<Button-1>", lambda e: self._toggle_help())
            w.bind("<Enter>", lambda e: self._help_hover(True))
            w.bind("<Leave>", lambda e: self._help_hover(False))
            w.config(cursor="hand2")

        # Help content (hidden by default)
        self.help_body = tk.Frame(self.root, bg=C["surface"],
                                   highlightbackground=C["muted"],
                                   highlightthickness=1)
        # don't pack yet

        help_text = (
            "  Decodes QR codes from images and extracts the embedded URL.\n"
            "\n"
            "  If the URL is a TOTP auth link (otpauth://totp/...),\n"
            "  it auto-extracts:\n"
            "    - Account   (user@domain)\n"
            "    - Secret    (TOTP key, used for auto code generation)\n"
            "    - Issuer    (service name, e.g. Duo, Google)\n"
            "\n"
            "  Use cases:\n"
            "    * DUO 2FA  -- save TOTP secret for fully automated login\n"
            "    * Google Authenticator backup -- extract & migrate keys\n"
            "    * Any otpauth:// QR -- decode without scanning on phone\n"
            "    * General QR -- decode URLs, WiFi configs, vCards, etc."
        )
        tk.Label(
            self.help_body, text=help_text, font=mono_font(9, text=help_text),
            bg=C["surface"], fg=C["subtext"], justify="left", anchor="w",
            padx=12, pady=10
        ).pack(fill="x")

        # Drop zone card
        self.drop_card = Card(self.root)
        self.drop_card.pack(fill="x", padx=20, pady=(12, 8))

        self.drop_inner = tk.Frame(self.drop_card, bg=C["surface"])
        self.drop_inner.pack(fill="x", padx=2, pady=2)

        self.drop_icon = tk.Label(
            self.drop_inner, text="[ + ]", font=mono_font(24, text="[ + ]"),
            bg=C["surface"], fg=C["muted"]
        )
        self.drop_icon.pack(pady=(20, 6))

        self.drop_hint = tk.Label(
            self.drop_inner,
            text="Ctrl+V  paste image\nClick to open file\nDrag file here",
            font=ui_font(10, text="Ctrl+V  paste image"), bg=C["surface"], fg=C["muted"],
            justify="center"
        )
        self.drop_hint.pack(pady=(0, 20))

        # Bind click on drop zone
        for w in (self.drop_card, self.drop_inner, self.drop_icon, self.drop_hint):
            w.bind("<Button-1>", lambda e: self.open_file())
            w.bind("<Enter>", self._drop_enter)
            w.bind("<Leave>", self._drop_leave)
            w.config(cursor="hand2")

        # Supported formats
        tk.Label(
            self.root, text="PNG  JPG  BMP  GIF  WEBP",
            font=ui_font(9, text="PNG  JPG  BMP  GIF  WEBP"), bg=C["bg"], fg=C["muted"]
        ).pack(padx=20, pady=(4, 0), anchor="w")

        # Preview
        self.preview_frame = tk.Frame(self.root, bg=C["bg"])
        self.preview_frame.pack(fill="x", padx=20, pady=4)

        self.preview_label = tk.Label(self.preview_frame, bg=C["bg"])
        self.preview_label.pack()

        # Button row
        btn_row = tk.Frame(self.root, bg=C["bg"])
        btn_row.pack(fill="x", padx=20, pady=(4, 8))

        FlatButton(btn_row, "[ Open ]", self.open_file,
                   bg=C["blue"], fg=C["crust"],
                   status_cb=self._flash_status).pack(side="left")

        FlatButton(btn_row, "[ Paste ]", self.paste_clipboard,
                   bg=C["blue"], fg=C["crust"],
                   status_cb=self._flash_status).pack(side="left", padx=(8, 0))

        FlatButton(btn_row, "[ Clear ]", self.clear_all,
                   bg=C["overlay"], fg=C["text"],
                   status_cb=self._flash_status).pack(side="right")

        FlatButton(btn_row, "[ Copy ]", self.copy_output,
                   bg=C["overlay"], fg=C["text"],
                   status_cb=self._flash_status).pack(side="right", padx=(0, 8))

        # Output card
        out_card = Card(self.root)
        out_card.pack(fill="both", expand=True, padx=20, pady=(0, 8))

        out_header = tk.Frame(out_card, bg=C["surface"])
        out_header.pack(fill="x", padx=8, pady=(8, 0))

        tk.Label(out_header, text="Output", font=ui_font(9, "bold", text="Output"),
                 bg=C["surface"], fg=C["subtext"]).pack(side="left")

        self.output = scrolledtext.ScrolledText(
            out_card, height=8, bg=C["surface"], fg=C["text"],
            font=mono_font(10, text="otpauth://"), relief="flat",
            insertbackground=C["text"], selectbackground=C["blue"],
            selectforeground=C["crust"], wrap="word", state="disabled",
            bd=0, padx=10, pady=8
        )
        self.output.pack(fill="both", expand=True, padx=8, pady=(4, 8))

        # Status bar
        self.status = tk.Label(
            self.root, text="Ready", bg=C["mantle"], fg=C["muted"],
            font=ui_font(8, text="Ready"), anchor="w", padx=10, pady=4
        )
        self.status.pack(side="bottom", fill="x")

    # -- Bindings --

    def _bind(self):
        self.root.bind("<Control-v>", lambda e: self.paste_clipboard())
        self.root.bind("<Control-V>", lambda e: self.paste_clipboard())

        # Drag and drop
        try:
            import windnd
            windnd.hook_dropfiles(self.root, func=self._on_drop)
        except (ImportError, Exception):
            try:
                import tkinterdnd2
                self.root.drop_target_register(tkinterdnd2.DND_FILES)
                self.root.dnd_bind("<<Drop>>", self._on_tkdnd_drop)
            except (ImportError, Exception):
                pass

        # Right-click menu
        self.root.bind("<Button-3>", self._context_menu)

    IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".tiff", ".tif"}

    def _is_image(self, path: str) -> bool:
        return os.path.splitext(path)[1].lower() in self.IMAGE_EXTS

    def _on_drop(self, files):
        try:
            paths = []
            for f in files:
                paths.append(f.decode("utf-8") if isinstance(f, bytes) else f)

            if len(paths) > 1:
                self._flash_status(f"Dropped {len(paths)} files, using first image", color=C["yellow"])

            for path in paths:
                if not os.path.isfile(path):
                    self._set_output(f"[ERROR] File not found:\n  {path}")
                    self._flash_status("File not found", color=C["red"])
                    return
                if not self._is_image(path):
                    ext = os.path.splitext(path)[1] or "(none)"
                    self._set_output(f"[ERROR] Not a supported image:\n  {path}\n  Got: {ext}")
                    self._flash_status("Unsupported format", color=C["red"])
                    return
                self.process_image(path)
                return
        except Exception as e:
            self._set_output(f"[ERROR] Drop failed: {e}")
            self._flash_status("Drop error", color=C["red"])

    def _on_tkdnd_drop(self, event):
        try:
            raw = event.data.strip().strip("{}")
            paths = [p.strip().strip("{}") for p in raw.split("} {")] if "} {" in raw else [raw]

            if len(paths) > 1:
                self._flash_status(f"Dropped {len(paths)} files, using first image", color=C["yellow"])

            for path in paths:
                if not os.path.isfile(path):
                    self._set_output(f"[ERROR] File not found:\n  {path}")
                    self._flash_status("File not found", color=C["red"])
                    return
                if not self._is_image(path):
                    ext = os.path.splitext(path)[1] or "(none)"
                    self._set_output(f"[ERROR] Not a supported image:\n  {path}\n  Got: {ext}")
                    self._flash_status("Unsupported format", color=C["red"])
                    return
                self.process_image(path)
                return
        except Exception as e:
            self._set_output(f"[ERROR] Drop failed: {e}")
            self._flash_status("Drop error", color=C["red"])

    def _context_menu(self, event):
        menu = tk.Menu(self.root, tearoff=0, bg=C["surface"], fg=C["text"],
                       activebackground=C["blue"], activeforeground=C["crust"],
                       font=ui_font(9, text="Paste Image"), relief="flat")
        menu.add_command(label="Paste Image", command=self.paste_clipboard)
        menu.add_command(label="Open File", command=self.open_file)
        menu.add_separator()
        menu.add_command(label="Copy Output", command=self.copy_output)
        menu.add_command(label="Clear", command=self.clear_all)
        menu.tk_popup(event.x_root, event.y_root)

    # -- Output helpers --

    def _set_output(self, text: str):
        self.output.config(state="normal")
        self.output.delete("1.0", "end")
        self.output.insert("1.0", text)
        self.output.config(state="disabled")

    def _flash_status(self, btn_text="", color=None, duration=600):
        """Flash a status message with accent color, then revert.
        Accepts button text (auto-mapped) or custom message string."""
        msg_map = {
            "[ Open ]":  "Opening file dialog...",
            "[ Paste ]": "Reading clipboard...",
            "[ Copy ]":  "Copied to clipboard",
            "[ Clear ]": "Cleared",
        }
        msg = msg_map.get(btn_text, btn_text)
        c = color or C["teal"]
        self.status.config(text=msg, fg=c)
        self.root.after(duration, lambda: self.status.config(text="Ready", fg=C["muted"]))

    def _drop_enter(self, e):
        self.drop_icon.config(fg=C["blue"])
        self.drop_hint.config(fg=C["subtext"])

    def _drop_leave(self, e):
        self.drop_icon.config(fg=C["muted"])
        self.drop_hint.config(fg=C["muted"])

    def _toggle_help(self):
        if self._help_open:
            self.help_body.pack_forget()
            self.help_arrow.config(text="[+]")
            self._help_open = False
        else:
            # insert help body right after the toggle bar
            self.help_body.pack(fill="x", padx=20, pady=(0, 4), after=self.help_toggle)
            self.help_arrow.config(text="[-]")
            self._help_open = True

    def _help_hover(self, entering):
        c = C["text"] if entering else C["muted"]
        self.help_arrow.config(fg=c)
        self.help_title.config(fg=C["text"] if entering else C["subtext"])

    def _show_preview(self, image_path: str):
        try:
            img = Image.open(image_path)
            img.thumbnail((200, 150))
            photo = ImageTk.PhotoImage(img)
            self.preview_label.config(image=photo, text="")
            self.preview_label.image = photo
        except Exception:
            self.preview_label.config(image="", text="")

    # -- Actions --

    def process_image(self, path: str):
        try:
            self._process_image_inner(path)
        except Exception as e:
            self._set_output(f"[ERROR] {type(e).__name__}: {e}")
            self._flash_status("Failed", color=C["red"])

    def _process_image_inner(self, path: str):
        if not os.path.isfile(path):
            self._set_output(f"[ERROR] File not found:\n  {path}")
            self._flash_status("File not found", color=C["red"])
            return

        if not self._is_image(path):
            ext = os.path.splitext(path)[1] or "(none)"
            self._set_output(f"[ERROR] Not a supported image format:\n  {path}\n  Got: {ext}\n  Supported: PNG JPG BMP GIF WEBP")
            self._flash_status("Unsupported format", color=C["red"])
            return

        # preview - ignore all errors
        try:
            img = Image.open(path)
            img.verify()  # check if it's a valid image
            img = Image.open(path)  # re-open after verify
            img.thumbnail((200, 150))
            photo = ImageTk.PhotoImage(img)
            self.preview_label.config(image=photo, text="")
            self.preview_label.image = photo
        except Exception:
            self.preview_label.config(image="", text="")

        name = os.path.basename(path)
        self.status.config(text=f"Decoding: {name}")
        self.root.update_idletasks()

        contents = decode_qr(path)

        if not contents:
            self._set_output("[!] No QR code detected in this image.")
            self.status.config(text="No QR code found")
            return

        lines = []
        for i, content in enumerate(contents):
            if len(contents) > 1:
                lines.append(f"--- QR #{i + 1} {'-' * 30}")

            lines.append(content)

            totp = parse_totp_url(content)
            if totp:
                lines.append(f"Account: {totp['account']}")
                lines.append(f"Secret:  {totp['secret']}")
                lines.append(f"Issuer:  {totp['issuer']}")
            lines.append("")

        self._set_output("\n".join(lines).strip())
        self.status.config(text=f"OK -- {len(contents)} QR code(s) decoded")

    def open_file(self):
        path = filedialog.askopenfilename(
            title="Select QR Image",
            filetypes=[
                ("Image files", "*.png *.jpg *.jpeg *.bmp *.gif *.webp"),
                ("All files", "*.*"),
            ]
        )
        if path:
            self.process_image(path)

    def paste_clipboard(self):
        try:
            clip = ImageGrab.grabclipboard()
        except Exception as e:
            self._set_output(f"[ERROR] Cannot read clipboard: {e}")
            self._flash_status("Clipboard error", color=C["red"])
            return

        if clip is None:
            if self._paste_from_raw_clipboard():
                return
            self._set_output("[!] No image in clipboard.\n    Copy or screenshot first, then paste.")
            return

        # Case 1: file path list (WeChat, Explorer, browser save-as, etc.)
        if isinstance(clip, list):
            paths = []
            for p in clip:
                try:
                    paths.append(p.decode("utf-8") if isinstance(p, bytes) else p)
                except Exception:
                    pass

            if len(paths) > 1:
                self._flash_status(f"Found {len(paths)} files, using first image", color=C["yellow"])

            for path in paths:
                if not os.path.isfile(path):
                    self._set_output(f"[ERROR] File not found:\n  {path}\n\n  Clipboard paths:\n"
                                     + "\n".join(f"    {p}" for p in paths))
                    self._flash_status("File not found", color=C["red"])
                    return
                if not self._is_image(path):
                    ext = os.path.splitext(path)[1] or "(none)"
                    self._set_output(f"[ERROR] Not a supported image:\n  {path}\n  Got: {ext}\n\n  Clipboard paths:\n"
                                     + "\n".join(f"    {p}" for p in paths))
                    self._flash_status("Unsupported format", color=C["red"])
                    return
                self.process_image(path)
                return

            self._set_output("[!] No image in clipboard.")
            return

        # Case 2: PIL Image object (screenshot, image editor copy, etc.)
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        try:
            clip.save(tmp.name)
            tmp.close()
            self.process_image(tmp.name)
        except Exception as e:
            self._set_output(f"[ERROR] Cannot save clipboard image: {e}")
            self._flash_status("Paste failed", color=C["red"])
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass

    def _paste_from_raw_clipboard(self) -> bool:
        """Fallback: read raw bitmap bytes directly from Windows clipboard."""
        try:
            import win32clipboard
            import io

            win32clipboard.OpenClipboard()
            try:
                # Try CF_DIB first
                for fmt in (win32clipboard.CF_DIB, 8):  # 8 = CF_DIB
                    try:
                        data = win32clipboard.GetClipboardData(fmt)
                        if data:
                            # CF_DIB data -> BMP file in memory
                            import struct
                            # BMP file header (14 bytes) + DIB header
                            bmp_header = struct.pack("<2sIHHI", b"BM",
                                                     14 + len(data), 0, 0, 14)
                            bmp_data = bmp_header + data
                            img = Image.open(io.BytesIO(bmp_data))
                            tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
                            img.save(tmp.name)
                            tmp.close()
                            self.process_image(tmp.name)
                            os.unlink(tmp.name)
                            return True
                    except Exception:
                        continue
            finally:
                win32clipboard.CloseClipboard()
        except Exception:
            pass
        return False

    def copy_output(self):
        content = self.output.get("1.0", "end").strip()
        if content:
            self.root.clipboard_clear()
            self.root.clipboard_append(content)
            self.status.config(text="Copied to clipboard")

    def clear_all(self):
        self.preview_label.config(image="", text="")
        self._set_output("")
        self.status.config(text="Ready")

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
