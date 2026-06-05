#!/usr/bin/env python3
"""VPN Auto-Connect GUI - 图形化 VPN 管理界面 / Visual VPN Manager

Features:
  - 一键连接/断开 / One-click connect/disconnect
  - Profile 管理 (添加/切换/删除) / Profile management
  - DUO 方法选择 (push/passcode) / DUO method selection
  - 实时状态显示 / Real-time connection status
  - Catppuccin Mocha 配色 / Catppuccin Mocha theme
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
import tkinter as tk
import webbrowser
from tkinter import ttk, messagebox, simpledialog
from pathlib import Path


def _startupinfo():
    """Return STARTUPINFO that hides the console window on Windows."""
    if sys.platform != "win32":
        return None
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0  # SW_HIDE
    return si


_CREATION_NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW
UI_LATIN_FONT = "Segoe UI"
UI_CJK_FONT = "SimSun"
MONO_LATIN_FONT = "Cascadia Code"
POWERSHELL_EXE = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
VPNCLI_EXE = Path(r"C:\Program Files (x86)\Cisco\Cisco Secure Client\vpncli.exe")
SESSION_LIMIT_SECONDS = 24 * 60 * 60
APP_USER_MODEL_ID = "VPNAutoConnect.GUI"
APP_ICON_FILE = Path(__file__).resolve().parents[1] / "assets" / "vpn-auto-connect.ico"
CISCO_VPN_STATE_FILES = [
    r"$env:ProgramData\Cisco\Cisco Secure Client\VPN\ConfigParam.bin",
    r"$env:ProgramData\Cisco\Cisco Secure Client\VPN\routechangesv4.bin",
    r"$env:ProgramData\Cisco\Cisco Secure Client\VPN\routechangesv6.bin",
]
DKU_GROUP_OPTIONS = ["-Default-", "Library Resources Only"]
DUKE_GROUP_OPTIONS = [
    "INTL-DUKE",
    "-Default-",
    "Fuqua School of Business",
    "Library Resources Only",
    "Nicholas Internal",
    "PRDN",
    "Protected_Data",
    "Public Safety",
    "prod-test-1",
]
DUKE_DEFAULT_GROUP = "INTL-DUKE"


def _has_cjk(text):
    return any("\u4e00" <= ch <= "\u9fff" for ch in str(text))


def ui_font(size, *styles, text=""):
    family = UI_CJK_FONT if _has_cjk(text) else UI_LATIN_FONT
    return (family, size, *styles)


def mono_font(size, *styles, text=""):
    family = UI_CJK_FONT if _has_cjk(text) else MONO_LATIN_FONT
    return (family, size, *styles)


def _set_windows_app_id():
    if sys.platform != "win32":
        return
    try:
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_USER_MODEL_ID)
    except Exception:
        pass


def _bind_right_click(widget, root):
    """Bind a right-click context menu with Copy / Copy All / Select All."""
    menu = tk.Menu(root, tearoff=0, bg=C["surface"], fg=C["text"],
                   activebackground=C["blue"], activeforeground=C["crust"],
                   font=ui_font(9, text="Copy"))

    def _show_menu(event):
        menu.delete(0, "end")
        try:
            sel = widget.selection_get()
        except tk.TclError:
            sel = ""
        if sel:
            menu.add_command(label="Copy", command=lambda: _copy_sel())
        menu.add_command(label="Copy All", command=lambda: _copy_all())
        menu.add_separator()
        menu.add_command(label="Select All", command=lambda: _select_all())
        menu.tk_popup(event.x_root, event.y_root)

    def _copy_sel():
        try:
            text = widget.selection_get()
            root.clipboard_clear()
            root.clipboard_append(text)
        except tk.TclError:
            pass

    def _copy_all():
        if hasattr(widget, "get"):
            text = widget.get("1.0", "end").strip()
            if text:
                root.clipboard_clear()
                root.clipboard_append(text)

    def _select_all():
        widget.tag_add("sel", "1.0", "end")
        widget.mark_set("insert", "1.0")
        widget.see("insert")

    widget.bind("<Button-3>", _show_menu)

# -- Catppuccin Mocha color palette --
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
    "peach":    "#fab387",
    "mauve":    "#cba6f7",
}

# -- Config paths --
CONFIG_DIR = Path.home() / ".vpn-auto-connect"
PROFILES_DIR = CONFIG_DIR / "profiles"
PROFILES_INDEX = CONFIG_DIR / "profiles.json"
ACTIVE_PROFILE_FILE = CONFIG_DIR / "active_profile"
LEGACY_CONFIG = CONFIG_DIR / "config.json"
LEGACY_CRED = CONFIG_DIR / "credentials.xml"

# -- VPN script path --
SCRIPT_DIR = Path(__file__).resolve().parent.parent
VPN_SCRIPT = SCRIPT_DIR / "vpn-auto-connect.ps1"


class FlatButton(tk.Canvas):
    """Custom flat button with rounded corners and hover effects."""

    def __init__(self, parent, text, command, bg, fg, hover_bg=None,
                 font=None, padx=18, pady=8, **kw):
        self.command = command
        self.bg = bg
        self.hover_bg = hover_bg or self._adjust(bg, 20)
        self.press_bg = self._adjust(bg, -25)
        self.fg = fg
        self.text = text
        self.font = font or ui_font(10, text=text)
        self._hovered = False

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

    def _draw(self, color):
        self.delete("all")
        w, h = self.winfo_reqwidth(), self.winfo_reqheight()
        self._round_rect(0, 0, w, h, self._r, color)
        self.create_text(w // 2, h // 2, text=self.text,
                         fill=self.fg, font=self.font)

    def _adjust(self, hex_color, amount):
        hex_color = hex_color.lstrip("#")
        r = max(0, min(255, int(hex_color[:2], 16) + amount))
        g = max(0, min(255, int(hex_color[2:4], 16) + amount))
        b = max(0, min(255, int(hex_color[4:6], 16) + amount))
        return f"#{r:02x}{g:02x}{b:02x}"

    def _on_enter(self, e):
        self._hovered = True
        self._draw(self.hover_bg)

    def _on_leave(self, e):
        self._hovered = False
        self._draw(self.bg)

    def _on_click(self, e):
        self._draw(self.press_bg)

    def _on_release(self, e):
        color = self.hover_bg if self._hovered else self.bg
        self._draw(color)
        self.command()


class ToolTip:
    """Small hover tooltip for compact action buttons."""

    def __init__(self, widget, text):
        self.widget = widget
        self.text = text
        self.tip = None
        widget.bind("<Enter>", self._show, add="+")
        widget.bind("<Leave>", self._hide, add="+")

    def _show(self, event=None):
        if self.tip:
            return
        x = self.widget.winfo_rootx() + 10
        y = self.widget.winfo_rooty() + self.widget.winfo_height() + 6
        self.tip = tk.Toplevel(self.widget)
        self.tip.wm_overrideredirect(True)
        self.tip.wm_geometry(f"+{x}+{y}")
        tk.Label(
            self.tip, text=self.text, font=ui_font(9, text=self.text),
            bg=C["crust"], fg=C["text"], padx=8, pady=4,
            highlightbackground=C["muted"], highlightthickness=1
        ).pack()

    def _hide(self, event=None):
        if self.tip:
            self.tip.destroy()
            self.tip = None


class Card(tk.Frame):
    """A card-like frame with border."""

    def __init__(self, parent, **kw):
        super().__init__(parent, bg=C["surface"],
                         highlightbackground=C["muted"],
                         highlightthickness=1, **kw)


class StatusIndicator(tk.Canvas):
    """Circular status indicator (green = connected, red = disconnected)."""

    def __init__(self, parent, size=16, **kw):
        super().__init__(parent, width=size, height=size, bg=parent["bg"],
                         highlightthickness=0, bd=0, **kw)
        self._size = size
        self._color = C["red"]
        self._draw()

    def _draw(self):
        self.delete("all")
        s = self._size
        self.create_oval(2, 2, s - 2, s - 2, fill=self._color, outline="")

    def set_connected(self):
        self._color = C["green"]
        self._draw()

    def set_disconnected(self):
        self._color = C["red"]
        self._draw()

    def set_checking(self):
        self._color = C["yellow"]
        self._draw()


class App:
    def __init__(self):
        _set_windows_app_id()
        self.root = tk.Tk()
        self.root.title("VPN Auto-Connect")
        self.root.geometry("500x650")
        self.root.resizable(False, False)
        self.root.configure(bg=C["bg"])
        self._set_window_icon()
        self._powershell = str(POWERSHELL_EXE) if POWERSHELL_EXE.exists() else "powershell"
        self._suspend_duo_sync = False
        self._ensure_profile_storage_ready()

        self._current_profile = self._load_active_profile()
        self._connected = False
        self._connecting = False
        self._session_tick_job = None
        self._session_timer_base = None

        self._build()
        self.duo_var.trace_add("write", self._on_duo_method_change)
        self._refresh_status()

    # -- Data helpers --

    def _ensure_profile_storage_ready(self):
        try:
            self._run_ps1_sync(["-MigrateOnly"], timeout=20)
        except Exception:
            # Keep GUI startup resilient; later actions will surface the real error.
            pass

    def _load_active_profile(self):
        if ACTIVE_PROFILE_FILE.exists():
            try:
                return ACTIVE_PROFILE_FILE.read_text(encoding="utf-8-sig").strip()
            except OSError:
                return None
        return None

    @staticmethod
    def _read_json_file(path):
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except (json.JSONDecodeError, OSError):
            return None

    def _load_profiles(self):
        if PROFILES_INDEX.exists():
            data = self._read_json_file(PROFILES_INDEX)
            if isinstance(data, list):
                return data
        return []

    def _load_profile_config(self, name):
        cfg_path = PROFILES_DIR / name / "config.json"
        if cfg_path.exists():
            data = self._read_json_file(cfg_path)
            if isinstance(data, dict):
                return data
        return None

    @staticmethod
    def _normalize_push_target(push_target):
        digits = re.sub(r"\D", "", push_target or "")
        if not digits:
            return ""
        normalized = str(int(digits))
        return "" if normalized == "0" else normalized

    @staticmethod
    def _config_duo_method(cfg):
        if not cfg:
            return "push"
        method = (cfg.get("DuoMethod") or "push").strip().lower()
        return method if method in {"push", "passcode"} else "push"

    @staticmethod
    def _set_entry_text(entry, value):
        entry.delete(0, "end")
        if value:
            entry.insert(0, value)
            entry.config(fg=C["text"])
            entry._placeholder_active = False
        elif getattr(entry, "_placeholder_text", ""):
            entry.insert(0, entry._placeholder_text)
            entry.config(fg=C["muted"])
            entry._placeholder_active = True
        else:
            entry.config(fg=C["text"])
            entry._placeholder_active = False

    def _save_active_profile(self, name):
        self._run_ps1_sync(["-Use", name], timeout=15)
        self._current_profile = name

    def _run_ps1_sync(self, args, timeout=30):
        cmd = [
            self._powershell, "-ExecutionPolicy", "Bypass",
            "-File", str(VPN_SCRIPT)
        ] + args
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
            startupinfo=_startupinfo(), creationflags=_CREATION_NO_WINDOW
        )
        stdout = (result.stdout or "").strip()
        stderr = (result.stderr or "").strip()
        if result.returncode != 0:
            raise RuntimeError(stderr or stdout or f"Command failed: {' '.join(args)}")
        return stdout

    def _set_duo_var(self, method):
        self._suspend_duo_sync = True
        try:
            self.duo_var.set(method)
        finally:
            self._suspend_duo_sync = False

    def _on_duo_method_change(self, *_args):
        if self._suspend_duo_sync:
            return
        method = self.duo_var.get().strip().lower()
        if method not in {"push", "passcode"}:
            return
        if not self._current_profile:
            return
        try:
            self._run_ps1_sync(["-Set", "duo", "-SetValue", method], timeout=20)
        except Exception as exc:
            self._log(f"[!!] Failed to save DUO Method: {exc}")
            messagebox.showerror("DUO Method", f"Failed to save DUO Method.\n\n{exc}")

    # -- UI Construction --

    def _set_window_icon(self):
        if APP_ICON_FILE.exists():
            try:
                self.root.iconbitmap(default=str(APP_ICON_FILE))
                return
            except tk.TclError:
                pass
        icon = tk.PhotoImage(width=32, height=32)
        # Fallback iconphoto keeps the window branded if iconbitmap is unavailable.
        for y in range(32):
            for x in range(32):
                d = ((x - 15.5) ** 2 + (y - 15.5) ** 2) ** 0.5
                if 12.6 <= d <= 14.4:
                    icon.put(C["blue"], (x, y))
                elif d < 12.6:
                    icon.put("#cde2ff", (x, y))
        icon.put("#4f9f73", to=(11, 13, 21, 16))
        icon.put("#4f9f73", to=(13, 16, 19, 23))
        icon.put("#5f6f8f", to=(14, 19, 18, 22))
        icon.put("#5f6f8f", to=(13, 9, 19, 11))
        icon.put("#5f6f8f", to=(12, 10, 14, 14))
        icon.put("#5f6f8f", to=(18, 10, 20, 14))
        self._window_icon = icon
        try:
            self.root.iconphoto(True, icon)
        except tk.TclError:
            pass

    def _build(self):
        # Header
        header = tk.Frame(self.root, bg=C["bg"])
        header.pack(fill="x", padx=20, pady=(18, 4))

        tk.Label(header, text="VPN Auto-Connect", font=ui_font(16, "bold", text="VPN Auto-Connect"),
                 bg=C["bg"], fg=C["text"]).pack(side="left")

        tk.Label(header, text="v1.0", font=ui_font(9, text="v1.0"),
                 bg=C["bg"], fg=C["muted"]).pack(side="left", padx=(6, 0), pady=(4, 0))

        # Status card
        status_card = Card(self.root)
        status_card.pack(fill="x", padx=20, pady=(12, 8))

        status_inner = tk.Frame(status_card, bg=C["surface"])
        status_inner.pack(fill="x", padx=12, pady=12)

        # Status row: indicator + text
        status_row = tk.Frame(status_inner, bg=C["surface"])
        status_row.pack(fill="x")

        self.status_indicator = StatusIndicator(status_row)
        self.status_indicator.pack(side="left", padx=(0, 8))

        self.status_label = tk.Label(
            status_row, text="Checking...", font=ui_font(14, "bold", text="Checking..."),
            bg=C["surface"], fg=C["text"]
        )
        self.status_label.pack(side="left")

        # IP and profile info
        self.info_label = tk.Label(
            status_inner, text="", font=ui_font(11, text="Server"),
            bg=C["surface"], fg=C["subtext"], anchor="w"
        )
        self.info_label.pack(fill="x", pady=(6, 0))

        self.session_label = tk.Label(
            status_inner, text="", font=ui_font(11, text="Duration"),
            bg=C["surface"], fg=C["text"], anchor="w"
        )
        self.session_label.pack(fill="x", pady=(4, 0))

        # Profile selector
        profile_card = Card(self.root)
        profile_card.pack(fill="x", padx=20, pady=(0, 8))

        profile_inner = tk.Frame(profile_card, bg=C["surface"])
        profile_inner.pack(fill="x", padx=12, pady=12)

        profile_header = tk.Frame(profile_inner, bg=C["surface"])
        profile_header.pack(fill="x")
        tk.Label(profile_header, text="Profile", font=ui_font(9, "bold", text="Profile"),
                 bg=C["surface"], fg=C["subtext"]).pack(side="left")
        self.profile_count_label = tk.Label(
            profile_header, text="", font=ui_font(9, text="1 profile"),
            bg=C["surface"], fg=C["muted"]
        )
        self.profile_count_label.pack(side="right")

        profile_row = tk.Frame(profile_inner, bg=C["surface"])
        profile_row.pack(fill="x", pady=(6, 0))

        self.profile_var = tk.StringVar()
        self.profile_combo = ttk.Combobox(
            profile_row, textvariable=self.profile_var,
            state="readonly", font=ui_font(10, text="DKU VPN")
        )
        self.profile_combo.pack(side="left", fill="x", expand=True)
        self.profile_combo.bind("<<ComboboxSelected>>", self._on_profile_change)

        FlatButton(profile_row, "Edit", self._edit_profile,
                   bg=C["overlay"], fg=C["text"], padx=8, pady=4
                   ).pack(side="left", padx=(4, 0))

        FlatButton(profile_row, "+", self._add_profile,
                   bg=C["green"], fg=C["crust"], padx=8, pady=4
                   ).pack(side="left", padx=(6, 0))

        FlatButton(profile_row, "-", self._remove_profile,
                   bg=C["red"], fg=C["crust"], padx=8, pady=4
                   ).pack(side="left", padx=(4, 0))

        FlatButton(profile_row, "Configs", self._show_configs,
                   bg=C["overlay"], fg=C["text"], padx=8, pady=4
                   ).pack(side="left", padx=(4, 0))

        # DUO method selector
        duo_card = Card(self.root)
        duo_card.pack(fill="x", padx=20, pady=(0, 8))

        duo_inner = tk.Frame(duo_card, bg=C["surface"])
        duo_inner.pack(fill="x", padx=12, pady=12)

        tk.Label(duo_inner, text="DUO Method", font=ui_font(9, "bold", text="DUO Method"),
                 bg=C["surface"], fg=C["subtext"]).pack(anchor="w")

        self.duo_var = tk.StringVar(value="push")
        duo_row = tk.Frame(duo_inner, bg=C["surface"])
        duo_row.pack(fill="x", pady=(6, 0))

        for method, label in [("push", "Push"), ("passcode", "TOTP")]:
            rb = tk.Radiobutton(
                duo_row, text=label, variable=self.duo_var, value=method,
                font=ui_font(9, text=label), bg=C["surface"], fg=C["text"],
                selectcolor=C["overlay"], activebackground=C["surface"],
                activeforeground=C["blue"], highlightthickness=0
            )
            rb.pack(side="left", padx=(0, 12))

        # Action buttons
        btn_frame = tk.Frame(self.root, bg=C["bg"])
        btn_frame.pack(fill="x", padx=20, pady=(8, 4))

        self.connect_btn = FlatButton(
            btn_frame, "[ Connect ]", self._connect,
            bg=C["blue"], fg=C["crust"]
        )
        self.connect_btn.pack(side="left")

        self.disconnect_btn = FlatButton(
            btn_frame, "[ Disconnect ]", self._disconnect,
            bg=C["overlay"], fg=C["text"]
        )
        self.disconnect_btn.pack(side="left", padx=(8, 0))

        refresh_btn = FlatButton(
            btn_frame, "[ Refresh ]", self._refresh_status,
            bg=C["overlay"], fg=C["text"]
        )
        refresh_btn.pack(side="right")

        ip_btn = FlatButton(
            btn_frame, "[ ip.me ]", self._open_ip_me,
            bg=C["teal"], fg=C["crust"], padx=12, pady=8
        )
        ip_btn.pack(side="right", padx=(0, 8))
        ToolTip(ip_btn, "Open ip.me to check your public IP address")

        # Log output
        log_card = Card(self.root)
        log_card.pack(fill="both", expand=True, padx=20, pady=(8, 8))

        log_header = tk.Frame(log_card, bg=C["surface"])
        log_header.pack(fill="x", padx=8, pady=(8, 0))

        tk.Label(log_header, text="Log", font=ui_font(9, "bold", text="Log"),
                 bg=C["surface"], fg=C["subtext"]).pack(side="left")

        FlatButton(log_header, "[ Copy ]", self._copy_log,
                   bg=C["overlay"], fg=C["text"], padx=8, pady=2
                   ).pack(side="right")

        FlatButton(log_header, "[ Clear ]", self._clear_log,
                   bg=C["overlay"], fg=C["text"], padx=8, pady=2
                   ).pack(side="right", padx=(0, 4))

        import tkinter.scrolledtext as st
        self.log_text = st.ScrolledText(
            log_card, height=10, bg=C["surface"], fg=C["text"],
            font=mono_font(9, text="VPN CLI"), relief="flat",
            insertbackground=C["text"], selectbackground=C["blue"],
            selectforeground=C["crust"], wrap="word",
            bd=0, padx=10, pady=8
        )
        self.log_text.pack(fill="both", expand=True, padx=8, pady=(4, 8))

        # Allow selection/copy but prevent editing
        def _log_key(e):
            if e.state & 4 and e.keysym.lower() in ("c", "a"):
                return None
            if e.keysym in ("Up", "Down", "Left", "Right", "Home", "End",
                            "Prior", "Next", "Shift_L", "Shift_R",
                            "Control_L", "Control_R"):
                return None
            return "break"

        self.log_text.bind("<Key>", _log_key)
        _bind_right_click(self.log_text, self.root)

        # Status bar
        self.status_bar = tk.Label(
            self.root, text="Ready", bg=C["mantle"], fg=C["muted"],
            font=ui_font(8, text="Ready"), anchor="w", padx=10, pady=4
        )
        self.status_bar.pack(side="bottom", fill="x")

        # Populate profiles
        self._refresh_profiles()

    # -- Profile management --

    @staticmethod
    def _display_name(name):
        """Map internal profile name to display name."""
        if name == "dku":
            return "DKU VPN"
        if name == "duke":
            return "Duke VPN"
        return name

    @staticmethod
    def _internal_name(display):
        """Map display name back to internal profile name."""
        if display == "DKU VPN":
            return "dku"
        if display == "Duke VPN":
            return "duke"
        return display

    def _resolve_profile_name(self, display):
        if not display:
            return ""
        return self._profile_map.get(display, self._internal_name(display))

    def _refresh_profiles(self):
        profiles = self._load_profiles()
        display_names = [self._display_name(p) for p in profiles]
        self.profile_combo["values"] = display_names
        self._profile_map = dict(zip(display_names, profiles))
        self.profile_count_label.config(text=f"{len(profiles)} profile(s)")

        if not profiles:
            self._current_profile = None
            self.profile_var.set("")
            self._set_duo_var("push")
            self.info_label.config(text="No profiles configured. Click + to add one.")
            self.session_label.config(text="")
            return

        active = self._current_profile
        if active and active in profiles:
            self.profile_var.set(self._display_name(active))
            self.profile_combo.current(display_names.index(self._display_name(active)))
        elif profiles:
            self.profile_var.set(self._display_name(profiles[0]))
            self.profile_combo.current(0)
            self._current_profile = profiles[0]

        # Show server info
        name = self._resolve_profile_name(self.profile_var.get())
        cfg = self._load_profile_config(name)
        if cfg:
            self.info_label.config(
                text=f"Server: {cfg.get('Server', '?')}  |  "
                     f"Port: {cfg.get('Port', '?')}  |  "
                     f"Protocol: {cfg.get('Protocol', '?')}"
            )
            self._set_duo_var(self._config_duo_method(cfg))
        self.session_label.config(text="")

    def _on_profile_change(self, event=None):
        display = self.profile_var.get()
        name = self._resolve_profile_name(display)
        if not name:
            return
        previous = self._current_profile
        try:
            self._save_active_profile(name)
        except Exception as exc:
            if previous:
                self.profile_var.set(self._display_name(previous))
            self._log(f"[!!] Failed to switch profile: {exc}")
            messagebox.showerror("Switch Profile", f"Failed to switch profile.\n\n{exc}")
            return

        self._current_profile = self._load_active_profile() or name
        selected_display = self._display_name(self._current_profile)
        if selected_display in self.profile_combo["values"]:
            self.profile_var.set(selected_display)

        cfg = self._load_profile_config(self._current_profile)
        if cfg:
            self.info_label.config(
                text=f"Server: {cfg.get('Server', '?')}  |  "
                     f"Port: {cfg.get('Port', '?')}  |  "
                     f"Protocol: {cfg.get('Protocol', '?')}"
            )
            self._set_duo_var(self._config_duo_method(cfg))
        self.session_label.config(text="")
        self._log(f"Switched to profile: {self._current_profile}")

    def _add_profile(self):
        self._open_profile_dialog()

    def _edit_profile(self):
        display = self.profile_var.get()
        if not display:
            messagebox.showinfo("Edit Profile", "No profile selected.")
            return
        self._open_profile_dialog(profile_name=self._resolve_profile_name(display))

    def _open_profile_dialog(self, profile_name=None):
        """Interactive add/edit profile dialog with DKU VPN preset."""
        edit_mode = bool(profile_name)
        existing_cfg = self._load_profile_config(profile_name) if edit_mode else None
        existing_username, has_password = self._load_profile_cred(profile_name) if edit_mode else ("", False)
        is_group_preset_profile = profile_name in {"dku", "duke"} if edit_mode else False
        preset_dialog_height = "420x360" if edit_mode else "420x320"
        custom_dialog_height = "420x670" if edit_mode else "420x620"

        dlg = tk.Toplevel(self.root)
        dlg.title("Edit VPN Profile" if edit_mode else "Add VPN Profile")
        dlg.geometry(preset_dialog_height if is_group_preset_profile else ("420x440" if edit_mode else "420x420"))
        dlg.configure(bg=C["bg"])
        dlg.resizable(False, False)
        dlg.transient(self.root)
        dlg.grab_set()

        # -- Preset selector --
        preset_frame = tk.Frame(dlg, bg=C["bg"])
        preset_frame.pack(fill="x", padx=20, pady=(16, 0))

        tk.Label(preset_frame, text="Preset", font=ui_font(9, "bold", text="Preset"),
                 bg=C["bg"], fg=C["subtext"]).pack(anchor="w")

        def _preset_defaults(kind):
            if kind == "dku":
                return {
                    "name": "dku",
                    "server": "portal.dukekunshan.edu.cn",
                    "port": "443",
                    "protocol": "ssl",
                }
            if kind == "duke":
                return {
                    "name": "duke",
                    "server": "vpn.duke.edu",
                    "port": "443",
                    "protocol": "ssl",
                }
            return {
                "name": profile_name if edit_mode else "",
                "server": "",
                "port": "443",
                "protocol": "ssl",
            }

        if edit_mode and existing_cfg:
            if (existing_cfg.get("Server") or "") == "portal.dukekunshan.edu.cn":
                preset_default = "dku"
            elif (existing_cfg.get("Server") or "") == "vpn.duke.edu":
                preset_default = "duke"
            else:
                preset_default = "custom"
        elif edit_mode:
            preset_default = profile_name if profile_name in {"dku", "duke"} else "custom"
        else:
            preset_default = "dku"
        preset_var = tk.StringVar(value=preset_default)
        preset_row = tk.Frame(preset_frame, bg=C["bg"])
        preset_row.pack(fill="x", pady=(4, 0))

        presets = {
            "dku": "DKU VPN",
            "duke": "Duke VPN",
            "custom": "Custom / Other",
        }
        for val, label in presets.items():
            rb = tk.Radiobutton(
                preset_row, text=label, variable=preset_var, value=val,
                font=ui_font(9, text=label), bg=C["bg"], fg=C["text"],
                selectcolor=C["overlay"], activebackground=C["bg"],
                activeforeground=C["blue"], highlightthickness=0
            )
            rb.pack(side="left", padx=(0, 16))

        # Separator
        sep = tk.Frame(dlg, bg=C["muted"], height=1)
        sep.pack(fill="x", padx=20, pady=(12, 0))

        # -- Helper to build a labeled entry row --
        def _make_row(parent, label, placeholder="", show=None):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text=label, font=ui_font(9, text=label),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            entry = tk.Entry(row, font=ui_font(10, text=placeholder or label), bg=C["surface"],
                             fg=C["text"], insertbackground=C["text"],
                             relief="flat", highlightthickness=1,
                             highlightbackground=C["muted"])
            if show:
                entry.config(show=show)
            entry.pack(side="left", fill="x", expand=True, padx=(8, 0))
            entry._placeholder_text = placeholder or ""
            entry._placeholder_active = False
            if placeholder:
                entry.insert(0, placeholder)
                entry.config(fg=C["muted"])
                entry._placeholder_active = True

                def _on_focus_in(e, ent=entry):
                    if getattr(ent, "_placeholder_active", False):
                        ent.selection_range(0, "end")
                        ent.icursor("end")

                def _on_keypress(e, ent=entry):
                    if not getattr(ent, "_placeholder_active", False):
                        return None
                    if len(e.keysym) == 1 or e.keysym in ("BackSpace", "Delete"):
                        ent.delete(0, "end")
                        ent.config(fg=C["text"])
                        ent._placeholder_active = False
                    return None

                def _on_focus_out(e, ent=entry, ph=placeholder):
                    if not ent.get().strip():
                        ent.delete(0, "end")
                        ent.insert(0, ph)
                        ent.config(fg=C["muted"])
                        ent._placeholder_active = True

                entry.bind("<FocusIn>", _on_focus_in)
                entry.bind("<KeyPress>", _on_keypress)
                entry.bind("<FocusOut>", _on_focus_out)
            return entry

        def _entry_value(entry):
            if getattr(entry, "_placeholder_active", False):
                return ""
            return entry.get().strip()

        def _make_pw_row(parent, label="Password"):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text=label, font=ui_font(9, text=label),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            entry = tk.Entry(row, font=ui_font(10, text=label), bg=C["surface"],
                             fg=C["text"], insertbackground=C["text"],
                             relief="flat", highlightthickness=1,
                             highlightbackground=C["muted"], show="*")
            entry.pack(side="left", fill="x", expand=True, padx=(8, 0))

            def _toggle():
                if entry.cget("show") == "*":
                    entry.config(show="")
                    btn.config(text="[Hide]")
                else:
                    entry.config(show="*")
                    btn.config(text="[Show]")

            btn = tk.Button(
                row, text="[Show]", font=ui_font(9, text="[Show]"),
                bg=C["surface"], fg=C["text"], relief="flat",
                highlightthickness=1, highlightbackground=C["muted"],
                command=_toggle, cursor="hand2", padx=4, pady=0
            )
            btn.pack(side="left", padx=(4, 0))
            return entry

        def _make_group_preset_row(parent, groups):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text="Group", font=ui_font(9, text="Group"),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            combo = ttk.Combobox(
                row,
                font=ui_font(10, text="-Default-"),
                state="readonly",
                values=groups,
            )
            combo.pack(side="left", fill="x", expand=True, padx=(8, 0))
            combo.set("-Default-")
            return combo

        def _make_hint(parent, text):
            tk.Label(
                parent, text=text, font=ui_font(8, text=text),
                bg=C["bg"], fg=C["muted"], justify="left", wraplength=360
            ).pack(anchor="w", pady=(4, 0))

        def _make_duo_row(parent):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text="DUO", font=ui_font(9, text="DUO"),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            method_var = tk.StringVar(value="push")
            method_row = tk.Frame(row, bg=C["bg"])
            method_row.pack(side="left", fill="x", expand=True, padx=(8, 0))
            for method, label in [("push", "Push"), ("passcode", "TOTP")]:
                rb = tk.Radiobutton(
                    method_row, text=label, variable=method_var, value=method,
                    font=ui_font(9, text=label), bg=C["bg"], fg=C["text"],
                    selectcolor=C["overlay"], activebackground=C["bg"],
                    activeforeground=C["blue"], highlightthickness=0
                )
                rb.pack(side="left", padx=(0, 12))
            return method_var

        def _build_group_preset_form(groups):
            form = tk.Frame(dlg, bg=C["bg"])
            netid = _make_row(form, "NetID", "your-netid")
            password_entry = _make_pw_row(form)
            group_combo = _make_group_preset_row(form, groups)
            duo_method_var = _make_duo_row(form)
            push_target_entry = _make_row(form, "PushTo", "optional: default 1")
            return {
                "form": form,
                "netid": netid,
                "password": password_entry,
                "group": group_combo,
                "duo_method": duo_method_var,
                "push_target": push_target_entry,
            }

        dku_preset = _build_group_preset_form(DKU_GROUP_OPTIONS)
        duke_preset = _build_group_preset_form(DUKE_GROUP_OPTIONS)
        duke_preset["group"].set(DUKE_DEFAULT_GROUP)

        # ===== Custom form =====
        custom_form = tk.Frame(dlg, bg=C["bg"])
        custom_name = _make_row(custom_form, "Name", "my-vpn")
        custom_username = _make_row(custom_form, "Username", "username")
        custom_password = _make_pw_row(custom_form)
        custom_server = _make_row(custom_form, "Server", "vpn.example.com")
        custom_port = _make_row(custom_form, "Port", "443")
        custom_protocol = _make_row(custom_form, "Protocol", "ssl")
        custom_group = _make_row(custom_form, "Group", "optional: group name")
        custom_duo_method = _make_duo_row(custom_form)
        custom_push_target = _make_row(custom_form, "PushTo", "optional: default 1")
        _make_hint(custom_form, "Optional. Mainly for accounts with multiple DUO phone numbers. Default is 1. Enter the Cisco DUO menu number you prefer, such as 1 or 2. If you only have one approved phone, leave it blank.")
        if edit_mode:
            _make_hint(custom_form, "Leave Password blank to keep the current saved password.")

        if edit_mode:
            self._set_entry_text(custom_name, profile_name)
            custom_name.config(state="disabled", disabledbackground=C["surface"], disabledforeground=C["muted"])

        def _target_name_for_preset(kind):
            if kind in {"dku", "duke"}:
                return kind
            if edit_mode:
                return profile_name
            return "__custom__"

        def _set_password_text(entry, value):
            entry.delete(0, "end")
            if value:
                entry.insert(0, value)

        def _profile_state_from_disk(target_name, selected_kind):
            resolved_name = target_name if target_name != "__custom__" else ""
            cfg = self._load_profile_config(resolved_name) if resolved_name else None
            username_value, has_saved_password = self._load_profile_cred(resolved_name) if resolved_name else ("", False)
            defaults = _preset_defaults(selected_kind)
            return {
                "name": profile_name if edit_mode else (resolved_name or defaults.get("name", "")),
                "username": username_value,
                "password": "",
                "server": defaults["server"] if selected_kind in {"dku", "duke"} else ((cfg or {}).get("Server", "")),
                "port": defaults["port"] if selected_kind in {"dku", "duke"} else ((cfg or {}).get("Port", "443")),
                "protocol": defaults["protocol"] if selected_kind in {"dku", "duke"} else ((cfg or {}).get("Protocol", "ssl")),
                "group": ((cfg or {}).get("Group", DUKE_DEFAULT_GROUP if selected_kind == "duke" else ("-Default-" if selected_kind == "dku" else ""))),
                "duo_method": self._config_duo_method(cfg),
                "push_target": ((cfg or {}).get("DuoPushTarget", "")),
                "has_password": has_saved_password,
                "exists": bool(cfg or has_saved_password),
            }

        def _collect_group_preset_state(kind, widgets):
            defaults = _preset_defaults(kind)
            return {
                "name": profile_name if edit_mode else defaults["name"],
                "username": _entry_value(widgets["netid"]),
                "password": widgets["password"].get(),
                "server": defaults["server"],
                "port": defaults["port"],
                "protocol": defaults["protocol"],
                "group": widgets["group"].get().strip() or (DUKE_DEFAULT_GROUP if kind == "duke" else "-Default-"),
                "duo_method": widgets["duo_method"].get(),
                "push_target": _entry_value(widgets["push_target"]),
                "has_password": widgets["password"].get().strip() != "",
                "exists": True,
            }

        def _collect_custom_state():
            return {
                "name": profile_name if edit_mode else _entry_value(custom_name),
                "username": _entry_value(custom_username),
                "password": custom_password.get(),
                "server": _entry_value(custom_server),
                "port": _entry_value(custom_port) or "443",
                "protocol": _entry_value(custom_protocol) or "ssl",
                "group": _entry_value(custom_group),
                "duo_method": custom_duo_method.get(),
                "push_target": _entry_value(custom_push_target),
                "has_password": custom_password.get().strip() != "",
                "exists": True,
            }

        def _collect_current_form_state(current_kind):
            if current_kind == "dku":
                return _collect_group_preset_state("dku", dku_preset)
            if current_kind == "duke":
                return _collect_group_preset_state("duke", duke_preset)
            return _collect_custom_state()

        def _apply_group_preset_state(widgets, state, groups):
            self._set_entry_text(widgets["netid"], state.get("username", ""))
            _set_password_text(widgets["password"], state.get("password", ""))
            fallback_group = DUKE_DEFAULT_GROUP if groups == DUKE_GROUP_OPTIONS else "-Default-"
            group_value = state.get("group") or fallback_group
            widgets["group"].set(group_value if group_value in groups else fallback_group)
            self._set_entry_text(widgets["push_target"], state.get("push_target", ""))
            widgets["duo_method"].set((state.get("duo_method") or "push"))

        def _apply_custom_state(state):
            if not edit_mode:
                self._set_entry_text(custom_name, state.get("name", ""))
            self._set_entry_text(custom_username, state.get("username", ""))
            _set_password_text(custom_password, state.get("password", ""))
            self._set_entry_text(custom_server, state.get("server", ""))
            self._set_entry_text(custom_port, state.get("port", "443"))
            self._set_entry_text(custom_protocol, state.get("protocol", "ssl"))
            self._set_entry_text(custom_group, state.get("group", ""))
            self._set_entry_text(custom_push_target, state.get("push_target", ""))
            custom_duo_method.set((state.get("duo_method") or "push"))

        def _populate_initial_state():
            state = {
                "name": profile_name if edit_mode else "",
                "username": existing_username,
                "password": "",
                "server": (existing_cfg or {}).get("Server", ""),
                "port": (existing_cfg or {}).get("Port", "443"),
                "protocol": (existing_cfg or {}).get("Protocol", "ssl"),
                "group": (existing_cfg or {}).get("Group", ""),
                "duo_method": self._config_duo_method(existing_cfg),
                "push_target": (existing_cfg or {}).get("DuoPushTarget", ""),
                "has_password": has_password,
                "exists": True,
            }
            _apply_custom_state(state)
            _apply_group_preset_state(dku_preset, state, DKU_GROUP_OPTIONS)
            _apply_group_preset_state(duke_preset, state, DUKE_GROUP_OPTIONS)

        _populate_initial_state()
        duke_preset["group"].set(((existing_cfg or {}).get("Group") or DUKE_DEFAULT_GROUP) if edit_mode and ((existing_cfg or {}).get("Group") in DUKE_GROUP_OPTIONS) else DUKE_DEFAULT_GROUP)
        current_preset_kind = {"value": preset_default}
        current_target_name = {"value": _target_name_for_preset(preset_default)}
        draft_states = {current_target_name["value"]: _profile_state_from_disk(current_target_name["value"], preset_default)}
        draft_states[current_target_name["value"]].update({
            "name": profile_name if edit_mode else draft_states[current_target_name["value"]]["name"],
            "username": existing_username,
            "password": "",
            "server": (existing_cfg or {}).get("Server", draft_states[current_target_name["value"]]["server"]) if existing_cfg else draft_states[current_target_name["value"]]["server"],
            "port": (existing_cfg or {}).get("Port", draft_states[current_target_name["value"]]["port"]) if existing_cfg else draft_states[current_target_name["value"]]["port"],
            "protocol": (existing_cfg or {}).get("Protocol", draft_states[current_target_name["value"]]["protocol"]) if existing_cfg else draft_states[current_target_name["value"]]["protocol"],
            "group": (existing_cfg or {}).get("Group", draft_states[current_target_name["value"]]["group"]) if existing_cfg else draft_states[current_target_name["value"]]["group"],
            "duo_method": self._config_duo_method(existing_cfg),
            "push_target": (existing_cfg or {}).get("DuoPushTarget", "") if existing_cfg else draft_states[current_target_name["value"]]["push_target"],
            "has_password": has_password,
            "exists": True,
        })

        def toggle_preset(target=None, preserve_state=True):
            selected = target or preset_var.get()
            if preserve_state:
                current_state = _collect_current_form_state(current_preset_kind["value"])
                previous_state = draft_states.get(current_target_name["value"], {})
                current_state["has_password"] = bool(current_state.get("password")) or previous_state.get("has_password", False)
                current_state["exists"] = previous_state.get("exists", True)
                draft_states[current_target_name["value"]] = current_state
            next_target_name = _target_name_for_preset(selected)
            next_state = draft_states.get(next_target_name)
            if next_state is None:
                next_state = _profile_state_from_disk(next_target_name, selected)
                draft_states[next_target_name] = next_state
            if selected == "dku":
                state_for_form = dict(next_state)
                state_for_form.update(_preset_defaults("dku"))
                _apply_group_preset_state(dku_preset, state_for_form, DKU_GROUP_OPTIONS)
            elif selected == "duke":
                state_for_form = dict(next_state)
                state_for_form.update(_preset_defaults("duke"))
                _apply_group_preset_state(duke_preset, state_for_form, DUKE_GROUP_OPTIONS)
            else:
                _apply_custom_state(next_state)
            preset_var.set(selected)
            dku_preset["form"].pack_forget()
            duke_preset["form"].pack_forget()
            custom_form.pack_forget()
            if selected in {"dku", "duke"}:
                preset_widgets = dku_preset if selected == "dku" else duke_preset
                custom_form.pack_forget()
                preset_widgets["form"].pack(fill="x", padx=20, pady=(8, 0))
                dlg.geometry(preset_dialog_height)
            else:
                custom_form.pack(fill="x", padx=20, pady=(8, 0))
                dlg.geometry(custom_dialog_height)
            current_preset_kind["value"] = selected
            current_target_name["value"] = next_target_name

        for child in preset_row.winfo_children():
            if isinstance(child, tk.Radiobutton):
                value = child.cget("value")
                child.config(command=lambda v=value: toggle_preset(v))
        toggle_preset(preset_default, preserve_state=False)

        # -- Save logic --
        def on_save():
            current_state = _collect_current_form_state(current_preset_kind["value"])
            previous_state = draft_states.get(current_target_name["value"], {})
            current_state["has_password"] = bool(current_state.get("password")) or previous_state.get("has_password", False)
            current_state["exists"] = previous_state.get("exists", True)
            draft_states[current_target_name["value"]] = current_state

            save_items = []
            for target_name, state in draft_states.items():
                save_state = dict(state)
                if target_name == "__custom__":
                    save_name = save_state.get("name", "").strip()
                else:
                    save_name = target_name
                save_state["resolved_name"] = save_name
                save_items.append(save_state)

            if edit_mode:
                save_items.sort(key=lambda item: item["resolved_name"] == profile_name)

            for state in save_items:
                name = state.get("resolved_name", "").strip()
                username = (state.get("username") or "").strip()
                password = (state.get("password") or "").strip()
                server = (state.get("server") or "").strip()
                port = (state.get("port") or "443").strip() or "443"
                protocol = (state.get("protocol") or "ssl").strip() or "ssl"
                group = state.get("group") or ""
                duo_method = state.get("duo_method") or "push"
                push_target = state.get("push_target") or ""
                has_saved_password = bool(state.get("has_password"))
                exists_on_disk = bool(state.get("exists"))

                if not name:
                    messagebox.showerror("Error", "Name is required for custom profile.")
                    return
                if not username:
                    messagebox.showerror("Error", f"Username is required for profile '{name}'.")
                    return
                if not server:
                    messagebox.showerror("Error", f"Server is required for profile '{name}'.")
                    return
                if not exists_on_disk and not password:
                    if edit_mode:
                        messagebox.showerror("Error", f"Password is required for new profile '{name}'.")
                    else:
                        messagebox.showerror("Error", "Password is required unless you keep the current saved password.")
                    return

                preserve_password = edit_mode and not password and has_saved_password
                save_ok = self._save_profile(
                    name, server, group, port, protocol, username, password,
                    push_target, duo_method=duo_method, preserve_password=preserve_password,
                    action="updated" if edit_mode else "added",
                    set_active=(name == profile_name) if edit_mode else True,
                    refresh_ui=False
                )
                if not save_ok:
                    return
                state["exists"] = True
                state["has_password"] = True if (password or preserve_password) else state.get("has_password", False)

            if edit_mode:
                self._current_profile = profile_name
                self._refresh_profiles()
                if self._current_profile:
                    self.profile_var.set(self._display_name(self._current_profile))
                    cfg = self._load_profile_config(self._current_profile)
                    if cfg:
                        self._set_duo_var(self._config_duo_method(cfg))
                self._log(f"Updated {len(save_items)} profile(s) from one edit session")
            dlg.destroy()

        # -- Buttons --
        btn_row = tk.Frame(dlg, bg=C["bg"])
        btn_row.pack(fill="x", padx=20, pady=(16, 0))
        FlatButton(btn_row, "[ Save ]", on_save,
                   bg=C["green"], fg=C["crust"]).pack(side="left")
        FlatButton(btn_row, "[ Cancel ]", dlg.destroy,
                   bg=C["overlay"], fg=C["text"]).pack(side="left", padx=(8, 0))

    def _save_profile(self, name, server, group, port, protocol, username, password,
                      push_target="", duo_method="push", preserve_password=False, action="added",
                      set_active=True, refresh_ui=True):
        """Save or update a profile through the PowerShell core script."""
        args = [
            "-ProfileUpsert",
            "-ProfileName", name,
            "-Server", server,
            "-Group", group,
            "-Port", port,
            "-Protocol", protocol,
            "-Username", username,
            "-DuoMethod", (duo_method or "push"),
            "-PushTo", (push_target or ""),
        ]
        if set_active:
            args.append("-SetActive")
        if preserve_password:
            args.append("-PreservePassword")
        else:
            args.extend(["-Password", password])

        try:
            output = self._run_ps1_sync(args, timeout=40)
            snapshot = json.loads(output) if output else {}
        except Exception as exc:
            self._log(f"[!!] Failed to save profile '{name}': {exc}")
            messagebox.showerror("Save Profile", f"Failed to save profile.\n\n{exc}")
            return False

        saved_name = snapshot.get("name", name)
        if set_active:
            self._current_profile = saved_name
        if refresh_ui:
            self._refresh_profiles()
        cfg = self._load_profile_config(saved_name) or {
            "DuoMethod": snapshot.get("duoMethod", "push")
        }
        if refresh_ui and set_active:
            self._set_duo_var(self._config_duo_method(cfg))
        self._log(f"Profile '{saved_name}' {action}: {username}@{server}")
        return True

    def _remove_profile(self):
        display = self.profile_var.get()
        if not display:
            return
        name = self._resolve_profile_name(display)
        if not messagebox.askyesno("Confirm", f"Delete profile '{display}'?"):
            return
        try:
            self._run_ps1_sync(["-Rm", name, "-Force"], timeout=20)
        except Exception as exc:
            self._log(f"[!!] Failed to delete profile '{name}': {exc}")
            messagebox.showerror("Delete Profile", f"Failed to delete profile.\n\n{exc}")
            return

        self._current_profile = self._load_active_profile()
        self._refresh_profiles()
        self._log(f"Profile '{name}' deleted")

    def _load_profile_cred(self, name):
        """Load credentials for a profile (username only, password masked)."""
        cred_path = PROFILES_DIR / name / "credentials.xml"
        if cred_path.exists():
            data = self._read_json_file(cred_path)
            if isinstance(data, dict):
                username = data.get("Username", "")
                has_pw = bool(data.get("Password", ""))
                return username, has_pw
        return "", False

    def _load_configs_payload(self):
        payload = self._run_ps1_sync(["-ConfigJson"], timeout=20)
        return json.loads(payload) if payload else {"activeProfile": None, "profiles": []}

    def _show_configs(self):
        """Show a dialog listing all profiles with their full config and credentials."""
        try:
            payload = self._load_configs_payload()
        except Exception as exc:
            self._log(f"[!!] Failed to load configs: {exc}")
            messagebox.showerror("Configs", f"Failed to load configs.\n\n{exc}")
            return

        profiles = payload.get("profiles", [])
        if not profiles:
            messagebox.showinfo("Configs", "No profiles configured.")
            return

        dlg = tk.Toplevel(self.root)
        dlg.title("Configs")
        dlg.geometry("480x360")
        dlg.configure(bg=C["bg"])
        dlg.resizable(False, False)
        dlg.transient(self.root)
        dlg.grab_set()

        tk.Label(dlg, text=f"Total: {len(profiles)} profile(s)",
                 font=ui_font(11, "bold", text=f"Total: {len(profiles)} profile(s)"),
                 bg=C["bg"], fg=C["text"]).pack(anchor="w", padx=20, pady=(14, 6))

        import tkinter.scrolledtext as st_cfg
        text_area = st_cfg.ScrolledText(
            dlg, bg=C["surface"], fg=C["text"],
            font=mono_font(9, text="Config"), relief="flat", wrap="word",
            insertbackground=C["text"], selectbackground=C["blue"],
            selectforeground=C["crust"], bd=0, padx=10, pady=8
        )
        text_area.pack(fill="both", expand=True, padx=20, pady=(0, 12))

        for profile in profiles:
            profile_name = profile.get("name", "")
            is_group_preset = profile_name in {"dku", "duke"}
            display = profile.get("displayName") or self._display_name(profile.get("name", ""))
            marker = " *" if profile.get("isActive") else "  "
            text_area.insert("end", f"{marker}{display}\n", "name")
            text_area.insert("end", f"    NetID:      {profile.get('username') or '-'}\n")
            text_area.insert("end", f"    Password:   {'(saved)' if profile.get('hasPassword') else '(none)'}\n")
            text_area.insert("end", f"    Server:     {profile.get('server') or '-'}\n")
            if not is_group_preset:
                text_area.insert("end", f"    Port:       {profile.get('port') or '-'}\n")
                text_area.insert("end", f"    Protocol:   {profile.get('protocol') or '-'}\n")
            text_area.insert("end", f"    Group:      {profile.get('group') or '-'}\n")
            text_area.insert("end", f"    DUO Method: {profile.get('duoMethod') or 'push'}\n")
            text_area.insert("end", f"    PushTo:     {profile.get('pushTo') or '(blank, auto menu)'}\n")
            text_area.insert("end", f"    TOTP:       {'(saved)' if profile.get('hasTotp') else '(not set)'}\n")
            text_area.insert("end", "\n")

        text_area.tag_config("name", foreground=C["blue"])

        # Allow selection/copy but prevent editing
        def _on_key(e):
            if e.state & 4 and e.keysym.lower() in ("c", "a"):
                return None
            if e.keysym in ("Up", "Down", "Left", "Right", "Home", "End",
                            "Prior", "Next", "Shift_L", "Shift_R",
                            "Control_L", "Control_R"):
                return None
            return "break"

        text_area.bind("<Key>", _on_key)
        text_area.bind("<Control-c>", lambda e: None)
        _bind_right_click(text_area, dlg)

        btn_row_cfg = tk.Frame(dlg, bg=C["bg"])
        btn_row_cfg.pack(fill="x", padx=20, pady=(0, 14))

        def _copy_all():
            dlg.clipboard_clear()
            dlg.clipboard_append(text_area.get("1.0", "end").strip())

        FlatButton(btn_row_cfg, "[ Copy All ]", _copy_all,
                   bg=C["blue"], fg=C["crust"]).pack(side="left")
        FlatButton(btn_row_cfg, "[ Close ]", dlg.destroy,
                   bg=C["overlay"], fg=C["text"]).pack(side="right")

    # -- VPN operations --

    @staticmethod
    def _format_elapsed(seconds):
        return f"{seconds:.1f}s"

    @staticmethod
    def _parse_stat_line(output, patterns):
        for pattern in patterns:
            match = re.search(pattern, output, re.MULTILINE)
            if match:
                return match.group(1).strip()
        return ""

    @staticmethod
    def _duration_to_seconds(value):
        if not value:
            return None
        match = re.search(r"(?:(\d+)\s+days?,?\s*)?(\d{1,2}):(\d{2}):(\d{2})", value, re.IGNORECASE)
        if not match:
            return None
        days = int(match.group(1) or 0)
        hours = int(match.group(2))
        minutes = int(match.group(3))
        seconds = int(match.group(4))
        return days * 86400 + hours * 3600 + minutes * 60 + seconds

    @staticmethod
    def _seconds_to_hms(seconds):
        seconds = max(0, int(seconds))
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"

    def _remaining_from_duration(self, duration):
        elapsed = self._duration_to_seconds(duration)
        if elapsed is None:
            return ""
        return self._seconds_to_hms(SESSION_LIMIT_SECONDS - elapsed)

    def _set_session_timer(self, duration, remaining):
        elapsed_seconds = self._duration_to_seconds(duration)
        remaining_seconds = self._duration_to_seconds(remaining)
        if elapsed_seconds is None:
            self._session_timer_base = None
            return
        if remaining_seconds is None:
            remaining_seconds = max(0, SESSION_LIMIT_SECONDS - elapsed_seconds)
        self._session_timer_base = {
            "elapsed": elapsed_seconds,
            "remaining": remaining_seconds,
            "monotonic": time.monotonic(),
        }

    def _render_session_timer(self):
        if not self._session_timer_base:
            return False
        delta = int(time.monotonic() - self._session_timer_base["monotonic"])
        duration = self._seconds_to_hms(self._session_timer_base["elapsed"] + delta)
        remaining = self._seconds_to_hms(self._session_timer_base["remaining"] - delta)
        self.session_label.config(text=f"Remaining: {remaining}  |  Duration: {duration}")
        return True

    def _schedule_session_tick(self):
        if self._session_tick_job:
            return

        def tick():
            self._session_tick_job = None
            if not self._connected:
                return
            if self._render_session_timer():
                self._session_tick_job = self.root.after(1000, tick)

        self._session_tick_job = self.root.after(1000, tick)

    def _cancel_session_tick(self):
        if self._session_tick_job:
            try:
                self.root.after_cancel(self._session_tick_job)
            except tk.TclError:
                pass
            self._session_tick_job = None

    def _query_vpn_session_timing(self):
        paths = "@(\n" + ",\n".join(f'    "{path}"' for path in CISCO_VPN_STATE_FILES) + "\n)"
        command = f"""
$paths = {paths}
$files = @($paths | Where-Object {{ Test-Path $_ }} | ForEach-Object {{ Get-Item $_ }})
if (-not $files -or $files.Count -eq 0) {{ return }}
$startFile = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$elapsed = [int]((Get-Date) - $startFile.LastWriteTime).TotalSeconds
if ($elapsed -lt 0 -or $elapsed -gt {SESSION_LIMIT_SECONDS}) {{ return }}
[pscustomobject]@{{
  elapsed = $elapsed
  remaining = [Math]::Max(0, {SESSION_LIMIT_SECONDS} - $elapsed)
  source = $startFile.Name
}} | ConvertTo-Json -Compress
"""
        try:
            result = subprocess.run(
                [self._powershell, "-NoProfile", "-Command", command],
                capture_output=True,
                text=True,
                timeout=10,
                startupinfo=_startupinfo(),
                creationflags=_CREATION_NO_WINDOW,
            )
            payload = result.stdout.strip()
            if not payload:
                return {}
            data = json.loads(payload)
            elapsed = int(data.get("elapsed", 0))
            remaining = int(data.get("remaining", 0))
            return {
                "duration": self._seconds_to_hms(elapsed),
                "remaining": self._seconds_to_hms(remaining),
            }
        except Exception:
            return {}

    def _query_vpn_ip(self):
        try:
            result = subprocess.run(
                [self._powershell, "-NoProfile", "-Command",
                 "$cisco = Get-NetAdapter -ErrorAction SilentlyContinue | "
                 "Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'Cisco AnyConnect|Cisco Secure Client' -or $_.Name -match 'Cisco|AnyConnect') }; "
                 "$addr = $cisco | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | "
                 "Where-Object { $_.IPAddress -and $_.IPAddress -notmatch '^169\\.254\\.' -and $_.IPAddress -notmatch '^127\\.' } | "
                 "Select-Object -First 1 -ExpandProperty IPAddress; "
                 "if (-not $addr) { "
                 "  $addr = Get-NetAdapter | Where-Object Status -eq Up | "
                 "    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | "
                 "    Where-Object IPAddress -match '^10\\.' | "
                 "    Select-Object -First 1 -ExpandProperty IPAddress "
                 "}; "
                 "$addr"],
                capture_output=True, text=True, timeout=10,
                startupinfo=_startupinfo(), creationflags=_CREATION_NO_WINDOW
            )
            return result.stdout.strip()
        except Exception:
            return ""

    def _query_vpn_stats(self):
        if self._connecting:
            return {}
        timing = self._query_vpn_session_timing()
        if not VPNCLI_EXE.exists():
            return timing
        try:
            proc = subprocess.Popen(
                [str(VPNCLI_EXE), "-s"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                startupinfo=_startupinfo(),
                creationflags=_CREATION_NO_WINDOW,
            )
            stdout, stderr = proc.communicate("stats\nexit\n", timeout=10)
            output = f"{stdout}\n{stderr}"
            stats = {
                "state": self._parse_stat_line(output, [
                    r"连接状态：\s*(.+)",
                    r"Connection State:\s*(.+)",
                    r">>\s*state:\s*(.+)",
                ]),
                "duration": self._parse_stat_line(output, [
                    r"持续时间：\s*([0-9:]+)",
                    r"Duration:\s*([0-9:]+)",
                ]),
                "remaining": self._parse_stat_line(output, [
                    r"剩余(?:会话)?(?:时间|时长)：\s*(.+)",
                    r"(?:会话)?(?:时间|时长)剩余：\s*(.+)",
                    r"Remaining(?: Session)? Time:\s*(.+)",
                    r"Session Time Remaining:\s*(.+)",
                    r"Time Remaining:\s*(.+)",
                ]),
                "server": self._parse_stat_line(output, [
                    r"Server Address：\s*(.+)",
                    r"Server Address:\s*(.+)",
                ]),
                "client_ip": self._parse_stat_line(output, [
                    r"客户端地址 \(IPv4\)：\s*(.+)",
                    r"Client Address \(IPv4\):\s*(.+)",
                ]),
                "session_disconnect": self._parse_stat_line(output, [
                    r"会话断开：\s*(.+)",
                    r"Session Disconnect:\s*(.+)",
                ]),
            }
            if timing:
                stats["duration"] = stats.get("duration") or timing.get("duration", "")
                stats["remaining"] = stats.get("remaining") or timing.get("remaining", "")
            return stats
        except Exception:
            return timing

    def _current_profile_server(self):
        display = self.profile_var.get()
        name = self._resolve_profile_name(display) if display else ""
        cfg = self._load_profile_config(name) if name else None
        if cfg and cfg.get("Server"):
            return str(cfg.get("Server")).strip()
        return ""

    def _resolve_status_server(self, stats=None):
        stats = stats or {}
        server = str(stats.get("server") or "").strip()
        if server and server != "不可用":
            return server
        return self._current_profile_server()

    def _refresh_connected_stats(self, delay_ms=1500):
        def worker():
            if self._connecting or not self._connected:
                return
            stats = self._query_vpn_stats()
            if not stats:
                return
            ip = self._query_vpn_ip()
            if ip:
                self.root.after(0, self._set_connected, ip, stats)

        self.root.after(delay_ms, lambda: threading.Thread(target=worker, daemon=True).start())

    def _poll_vpn_ip(self, max_seconds=20, interval=0.5):
        deadline = time.time() + max_seconds
        while time.time() < deadline:
            ip = self._query_vpn_ip()
            if ip:
                return ip
            time.sleep(interval)
        return ""

    @staticmethod
    def _parse_vpn_result(output):
        match = re.search(r"VPN_RESULT=(CONNECTED|DISCONNECTED|FAILED|TIMEOUT)", output)
        return match.group(1) if match else ""

    def _stream_process(self, cmd, timeout):
        output_lines = []
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            startupinfo=_startupinfo(),
            creationflags=_CREATION_NO_WINDOW,
        )

        def pump(pipe):
            for raw_line in iter(pipe.readline, ""):
                line = raw_line.rstrip()
                if not line:
                    continue
                output_lines.append(line)
                self.root.after(0, self._log, line)
            pipe.close()

        stdout_thread = threading.Thread(target=pump, args=(proc.stdout,), daemon=True)
        stderr_thread = threading.Thread(target=pump, args=(proc.stderr,), daemon=True)
        stdout_thread.start()
        stderr_thread.start()

        timed_out = False
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        finally:
            stdout_thread.join(timeout=2)
            stderr_thread.join(timeout=2)

        return proc.returncode, "\n".join(output_lines), timed_out

    def _run_vpn_cmd(self, args, timeout=120):
        """Run vpn-auto-connect.ps1 with given args in a thread."""
        def worker():
            start_ts = time.time()
            ip = ""
            result_marker = ""
            is_connect = "-Connect" in args
            try:
                cmd = [
                    self._powershell, "-ExecutionPolicy", "Bypass",
                    "-File", str(VPN_SCRIPT)
                ] + args
                self.root.after(0, self._log, f"[..] Start command: vpn-auto-connect.ps1 {' '.join(args)}")
                self.root.after(0, self._log, f"[..] Stage 1: waiting for PowerShell process (timeout: {timeout}s)")
                returncode, output, timed_out = self._stream_process(cmd, timeout=timeout)
                result_marker = self._parse_vpn_result(output)
                elapsed = self._format_elapsed(time.time() - start_ts)

                if timed_out:
                    result_marker = "TIMEOUT"
                    self.root.after(0, self._log, f"[!!] Stage 1 timed out after {timeout}s")
                else:
                    self.root.after(
                        0, self._log,
                        f"[..] Stage 1 finished in {elapsed} (exit code: {returncode}, marker: {result_marker or 'none'})"
                    )

                if is_connect:
                    if result_marker != "CONNECTED":
                        self.root.after(0, self._log, "[..] Stage 2: polling VPN IP after process exit")
                        extended_poll = any(keyword in output for keyword in [
                            "Downloader is performing update checks",
                            "downloader is performing update checks",
                            "Downloading Cisco Secure Client",
                            "Downloading Cisco Secure Client VPN Profile",
                            "下载",
                            "组件",
                            "update checks",
                        ])
                        poll_seconds = 90 if extended_poll else 20
                        if extended_poll:
                            self.root.after(0, self._log, f"[..] Stage 2 extended to {poll_seconds}s because Cisco is still downloading/updating components")
                        ip = self._poll_vpn_ip(max_seconds=poll_seconds, interval=0.5)
                    else:
                        ip = self._query_vpn_ip()
                    if ip:
                        self.root.after(0, self._log, f"[OK] Stage 2 detected VPN IP: {ip}")
                    else:
                        self.root.after(0, self._log, "[!!] Stage 2 found no VPN tunnel IP")

                final_state = result_marker or "FAILED"
                if is_connect and ip:
                    final_state = "CONNECTED"
                elif timed_out:
                    final_state = "TIMEOUT"

                total_elapsed = self._format_elapsed(time.time() - start_ts)
                self.root.after(0, self._log, f"[==] Final state: {final_state} (elapsed: {total_elapsed})")

                # Detect authentication failures
                auth_fail = any(kw in output for kw in [
                    "Login denied", "Authentication failed", "认证失败",
                    "Login failed", "Access denied", "auth failed"
                ])
                if is_connect and auth_fail:
                    self.root.after(0, lambda: messagebox.showerror(
                        "Authentication Failed",
                        "Login denied. Please check your username and password.\n\n"
                        "If using DKU VPN, verify your NetID and password are correct."
                    ))

                if is_connect and ip:
                    self.root.after(0, self._set_connected, ip, {})
                    self.root.after(0, self._refresh_connected_stats)
                else:
                    self.root.after(0, self._refresh_status)
            except Exception as e:
                self.root.after(0, self._log, f"[!!] Error: {e}")
                self.root.after(0, self._refresh_status)
            finally:
                self._connecting = False
                self.root.after(0, lambda: self.connect_btn.config(state="normal"))

        self._connecting = True
        self.connect_btn.config(state="disabled")
        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def _connect(self):
        if self._connecting:
            return
        method = self.duo_var.get()
        self.session_label.config(text="")
        self._log(f"Connecting... (DUO: {method})")
        self._run_vpn_cmd(["-Connect", "-DuoMethod", method], timeout=240)

    def _disconnect(self):
        self._log("Disconnecting...")
        self._run_vpn_cmd(["-Disconnect"], timeout=30)

    def _open_ip_me(self):
        webbrowser.open("https://ip.me/")

    def _refresh_status(self):
        """Check VPN status by looking for the Cisco tunnel IP."""
        def worker():
            try:
                ip = self._query_vpn_ip()
                if ip:
                    stats = self._query_vpn_stats()
                    self.root.after(0, self._set_connected, ip, stats)
                else:
                    self.root.after(0, self._set_disconnected, {})
            except Exception:
                self.root.after(0, self._set_disconnected, {})

        self.status_indicator.set_checking()
        self.status_label.config(text="Checking...", fg=C["yellow"])
        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def _set_connected(self, ip, stats=None):
        self._connected = True
        stats = stats or {}
        self.status_indicator.set_connected()
        server = self._resolve_status_server(stats)
        status_text = f"Connected: {server}" if server else "Connected"
        self.status_label.config(text=status_text, fg=C["green"])
        name = self.profile_var.get() or "(unknown)"
        self.info_label.config(text=f"Profile: {name}  |  IP: {ip}")
        duration = stats.get("duration") or "00:00:00"
        remaining = stats.get("remaining") or self._remaining_from_duration(duration)
        self._set_session_timer(duration, remaining)
        if remaining:
            self.session_label.config(text=f"Remaining: {remaining}  |  Duration: {duration}")
        else:
            self.session_label.config(text=f"Duration: {duration}")
        self._schedule_session_tick()

    def _set_disconnected(self, stats=None):
        self._connected = False
        self._cancel_session_tick()
        self._session_timer_base = None
        stats = stats or {}
        self.status_indicator.set_disconnected()
        status_server = self._resolve_status_server(stats)
        status_text = f"Disconnected: {status_server}" if status_server else "Disconnected"
        self.status_label.config(text=status_text, fg=C["red"])
        display = self.profile_var.get() or "(no profile)"
        name = self._internal_name(display)
        cfg = self._load_profile_config(name)
        if cfg:
            self.info_label.config(
                text=f"Server: {cfg.get('Server', '?')}  |  "
                     f"Port: {cfg.get('Port', '?')}  |  "
                     f"Protocol: {cfg.get('Protocol', '?')}"
            )
        else:
            self.info_label.config(text="")
        duration = stats.get("duration")
        details = []
        if duration and duration != "00:00:00":
            details.append(f"Last duration: {duration}")
        self.session_label.config(text="  |  ".join(details))

    # -- Log --

    def _log(self, msg):
        stamp = time.strftime("%H:%M:%S")
        self.log_text.insert("end", f"[{stamp}] {msg}\n")
        self.log_text.see("end")

    def _clear_log(self):
        self.log_text.delete("1.0", "end")

    def _copy_log(self):
        content = self.log_text.get("1.0", "end").strip()
        if content:
            self.root.clipboard_clear()
            self.root.clipboard_append(content)

    # -- Main --

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
