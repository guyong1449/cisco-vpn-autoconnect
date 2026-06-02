#!/usr/bin/env python3
"""VPN Auto-Connect GUI - 图形化 VPN 管理界面 / Visual VPN Manager

Features:
  - 一键连接/断开 / One-click connect/disconnect
  - Profile 管理 (添加/切换/删除) / Profile management
  - DUO 方法选择 (push/phone/sms/passcode) / DUO method selection
  - 实时状态显示 / Real-time connection status
  - Catppuccin Mocha 配色 / Catppuccin Mocha theme
"""

import json
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
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


def _bind_right_click(widget, root):
    """Bind a right-click context menu with Copy / Copy All / Select All."""
    menu = tk.Menu(root, tearoff=0, bg=C["surface"], fg=C["text"],
                   activebackground=C["blue"], activeforeground=C["crust"],
                   font=("Segoe UI", 9))

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
                 font=("Segoe UI", 10), padx=18, pady=8, **kw):
        self.command = command
        self.bg = bg
        self.hover_bg = hover_bg or self._adjust(bg, 20)
        self.press_bg = self._adjust(bg, -25)
        self.fg = fg
        self.text = text
        self._hovered = False

        tmp = tk.Label(parent, text=text, font=font)
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
                         fill=self.fg, font=("Segoe UI", 10))

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
        self.root = tk.Tk()
        self.root.title("VPN Auto-Connect")
        self.root.geometry("500x650")
        self.root.resizable(False, False)
        self.root.configure(bg=C["bg"])

        self._current_profile = self._load_active_profile()
        self._connected = False
        self._connecting = False

        self._build()
        self._refresh_status()

    # -- Data helpers --

    def _load_active_profile(self):
        if ACTIVE_PROFILE_FILE.exists():
            return ACTIVE_PROFILE_FILE.read_text().strip()
        return None

    def _load_profiles(self):
        if PROFILES_INDEX.exists():
            try:
                return json.loads(PROFILES_INDEX.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        return []

    def _load_profile_config(self, name):
        cfg_path = PROFILES_DIR / name / "config.json"
        if cfg_path.exists():
            try:
                return json.loads(cfg_path.read_text())
            except (json.JSONDecodeError, OSError):
                pass
        return None

    def _save_active_profile(self, name):
        ACTIVE_PROFILE_FILE.write_text(name)

    # -- UI Construction --

    def _build(self):
        # Header
        header = tk.Frame(self.root, bg=C["bg"])
        header.pack(fill="x", padx=20, pady=(18, 4))

        tk.Label(header, text="VPN Auto-Connect", font=("Segoe UI", 16, "bold"),
                 bg=C["bg"], fg=C["text"]).pack(side="left")

        tk.Label(header, text="v1.0", font=("Segoe UI", 9),
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
            status_row, text="Checking...", font=("Segoe UI", 12, "bold"),
            bg=C["surface"], fg=C["yellow"]
        )
        self.status_label.pack(side="left")

        # IP and profile info
        self.info_label = tk.Label(
            status_inner, text="", font=("Segoe UI", 9),
            bg=C["surface"], fg=C["muted"], anchor="w"
        )
        self.info_label.pack(fill="x", pady=(6, 0))

        # Profile selector
        profile_card = Card(self.root)
        profile_card.pack(fill="x", padx=20, pady=(0, 8))

        profile_inner = tk.Frame(profile_card, bg=C["surface"])
        profile_inner.pack(fill="x", padx=12, pady=12)

        profile_header = tk.Frame(profile_inner, bg=C["surface"])
        profile_header.pack(fill="x")
        tk.Label(profile_header, text="Profile", font=("Segoe UI", 9, "bold"),
                 bg=C["surface"], fg=C["subtext"]).pack(side="left")
        self.profile_count_label = tk.Label(
            profile_header, text="", font=("Segoe UI", 9),
            bg=C["surface"], fg=C["muted"]
        )
        self.profile_count_label.pack(side="right")

        profile_row = tk.Frame(profile_inner, bg=C["surface"])
        profile_row.pack(fill="x", pady=(6, 0))

        self.profile_var = tk.StringVar()
        self.profile_combo = ttk.Combobox(
            profile_row, textvariable=self.profile_var,
            state="readonly", font=("Segoe UI", 10)
        )
        self.profile_combo.pack(side="left", fill="x", expand=True)
        self.profile_combo.bind("<<ComboboxSelected>>", self._on_profile_change)

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

        tk.Label(duo_inner, text="DUO Method", font=("Segoe UI", 9, "bold"),
                 bg=C["surface"], fg=C["subtext"]).pack(anchor="w")

        self.duo_var = tk.StringVar(value="push")
        duo_row = tk.Frame(duo_inner, bg=C["surface"])
        duo_row.pack(fill="x", pady=(6, 0))

        for method, label in [("push", "Push"), ("phone", "Phone"),
                               ("sms", "SMS"), ("passcode", "TOTP")]:
            rb = tk.Radiobutton(
                duo_row, text=label, variable=self.duo_var, value=method,
                font=("Segoe UI", 9), bg=C["surface"], fg=C["text"],
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

        FlatButton(
            btn_frame, "[ Refresh ]", self._refresh_status,
            bg=C["overlay"], fg=C["text"]
        ).pack(side="right")

        # Log output
        log_card = Card(self.root)
        log_card.pack(fill="both", expand=True, padx=20, pady=(8, 8))

        log_header = tk.Frame(log_card, bg=C["surface"])
        log_header.pack(fill="x", padx=8, pady=(8, 0))

        tk.Label(log_header, text="Log", font=("Segoe UI", 9, "bold"),
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
            font=("Cascadia Code", 9), relief="flat",
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
            font=("Segoe UI", 8), anchor="w", padx=10, pady=4
        )
        self.status_bar.pack(side="bottom", fill="x")

        # Populate profiles
        self._refresh_profiles()

    # -- Profile management --

    @staticmethod
    def _display_name(name):
        """Map internal profile name to display name."""
        return "DKU VPN" if name == "dku" else name

    @staticmethod
    def _internal_name(display):
        """Map display name back to internal profile name."""
        return "dku" if display == "DKU VPN" else display

    def _refresh_profiles(self):
        profiles = self._load_profiles()
        display_names = [self._display_name(p) for p in profiles]
        self.profile_combo["values"] = display_names
        self._profile_map = dict(zip(display_names, profiles))
        self.profile_count_label.config(text=f"{len(profiles)} profile(s)")

        if not profiles:
            self.info_label.config(text="No profiles configured. Click + to add one.")
            return

        active = self._current_profile
        if active and active in profiles:
            self.profile_var.set(self._display_name(active))
        elif profiles:
            self.profile_var.set(self._display_name(profiles[0]))
            self._current_profile = profiles[0]

        # Show server info
        name = self._internal_name(self.profile_var.get())
        cfg = self._load_profile_config(name)
        if cfg:
            self.info_label.config(
                text=f"Server: {cfg.get('Server', '?')}  |  "
                     f"Port: {cfg.get('Port', '?')}  |  "
                     f"Protocol: {cfg.get('Protocol', '?')}"
            )

    def _on_profile_change(self, event=None):
        display = self.profile_var.get()
        name = self._internal_name(display)
        self._current_profile = name
        self._save_active_profile(name)

        cfg = self._load_profile_config(name)
        if cfg:
            self.info_label.config(
                text=f"Server: {cfg.get('Server', '?')}  |  "
                     f"Port: {cfg.get('Port', '?')}  |  "
                     f"Protocol: {cfg.get('Protocol', '?')}"
            )
        self._log(f"Switched to profile: {name}")

    def _add_profile(self):
        """Interactive add profile dialog with DKU VPN preset."""
        dlg = tk.Toplevel(self.root)
        dlg.title("Add VPN Profile")
        dlg.geometry("420x440")
        dlg.configure(bg=C["bg"])
        dlg.resizable(False, False)
        dlg.transient(self.root)
        dlg.grab_set()

        # -- Preset selector --
        preset_frame = tk.Frame(dlg, bg=C["bg"])
        preset_frame.pack(fill="x", padx=20, pady=(16, 0))

        tk.Label(preset_frame, text="Preset", font=("Segoe UI", 9, "bold"),
                 bg=C["bg"], fg=C["subtext"]).pack(anchor="w")

        preset_var = tk.StringVar(value="dku")
        preset_row = tk.Frame(preset_frame, bg=C["bg"])
        preset_row.pack(fill="x", pady=(4, 0))

        presets = {
            "dku": "DKU VPN",
            "custom": "Custom / Other",
        }
        for val, label in presets.items():
            rb = tk.Radiobutton(
                preset_row, text=label, variable=preset_var, value=val,
                font=("Segoe UI", 9), bg=C["bg"], fg=C["text"],
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
            tk.Label(row, text=label, font=("Segoe UI", 9),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            entry = tk.Entry(row, font=("Segoe UI", 10), bg=C["surface"],
                             fg=C["text"], insertbackground=C["text"],
                             relief="flat", highlightthickness=1,
                             highlightbackground=C["muted"])
            if show:
                entry.config(show=show)
            entry.pack(side="left", fill="x", expand=True, padx=(8, 0))
            if placeholder:
                entry.insert(0, placeholder)
                entry.config(fg=C["muted"])

                def _on_in(e, ent=entry, ph=placeholder):
                    if ent.get() == ph:
                        ent.delete(0, "end")
                        ent.config(fg=C["text"])

                def _on_out(e, ent=entry, ph=placeholder):
                    if not ent.get().strip():
                        ent.delete(0, "end")
                        ent.insert(0, ph)
                        ent.config(fg=C["muted"])

                entry.bind("<FocusIn>", _on_in)
                entry.bind("<FocusOut>", _on_out)
            return entry

        def _make_pw_row(parent, label="Password"):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text=label, font=("Segoe UI", 9),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            entry = tk.Entry(row, font=("Segoe UI", 10), bg=C["surface"],
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
                row, text="[Show]", font=("Segoe UI", 9),
                bg=C["surface"], fg=C["text"], relief="flat",
                highlightthickness=1, highlightbackground=C["muted"],
                command=_toggle, cursor="hand2", padx=4, pady=0
            )
            btn.pack(side="left", padx=(4, 0))
            return entry

        def _make_group_row(parent):
            row = tk.Frame(parent, bg=C["bg"])
            row.pack(fill="x", pady=(6, 0))
            tk.Label(row, text="Group", font=("Segoe UI", 9),
                     bg=C["bg"], fg=C["subtext"], width=10, anchor="w").pack(side="left")
            combo = ttk.Combobox(row, font=("Segoe UI", 10), state="normal")
            combo.pack(side="left", fill="x", expand=True, padx=(8, 0))
            combo.insert(0, "-Default-")
            combo.config(foreground=C["muted"])

            def _focus_in(e):
                if combo.get() == "-Default-":
                    combo.delete(0, "end")
                    combo.config(foreground=C["text"])
            def _focus_out(e):
                if not combo.get().strip():
                    combo.insert(0, "-Default-")
                    combo.config(foreground=C["muted"])
            combo.bind("<FocusIn>", _focus_in)
            combo.bind("<FocusOut>", _focus_out)
            return combo

        # ===== DKU VPN form =====
        dku_form = tk.Frame(dlg, bg=C["bg"])
        dku_netid = _make_row(dku_form, "NetID", "your-netid")
        dku_password = _make_pw_row(dku_form)
        dku_group = _make_group_row(dku_form)

        # ===== Custom form =====
        custom_form = tk.Frame(dlg, bg=C["bg"])
        custom_name = _make_row(custom_form, "Name", "my-vpn")
        custom_username = _make_row(custom_form, "Username", "username")
        custom_password = _make_pw_row(custom_form)
        custom_server = _make_row(custom_form, "Server", "vpn.example.com")
        custom_port = _make_row(custom_form, "Port", "443")
        custom_protocol = _make_row(custom_form, "Protocol", "ssl")
        custom_group = _make_group_row(custom_form)

        def toggle_preset():
            if preset_var.get() == "dku":
                custom_form.pack_forget()
                dku_form.pack(fill="x", padx=20, pady=(8, 0))
                dlg.geometry("420x300")
            else:
                dku_form.pack_forget()
                custom_form.pack(fill="x", padx=20, pady=(8, 0))
                dlg.geometry("420x440")

        preset_var.trace_add("write", lambda *_: toggle_preset())
        toggle_preset()

        # -- Save logic --
        def on_save():
            if preset_var.get() == "dku":
                username = dku_netid.get().strip()
                password = dku_password.get().strip()
                group = dku_group.get().strip() or "-Default-"
                if not username or not password:
                    messagebox.showerror("Error", "NetID and Password are required.")
                    return
                name = "dku"
                server = "portal.dukekunshan.edu.cn"
                port = "443"
                protocol = "ssl"
            else:
                name = custom_name.get().strip()
                username = custom_username.get().strip()
                password = custom_password.get().strip()
                server = custom_server.get().strip()
                port = custom_port.get().strip() or "443"
                protocol = custom_protocol.get().strip() or "ssl"
                group = custom_group.get().strip() or "-Default-"
                if not name:
                    messagebox.showerror("Error", "Name is required for custom profile.")
                    return
                if not username or not password:
                    messagebox.showerror("Error", "Username and Password are required.")
                    return
                if not server:
                    messagebox.showerror("Error", "Server is required for custom profile.")
                    return

            self._save_profile(name, server, group, port, protocol, username, password)
            dlg.destroy()

        # -- Buttons --
        btn_row = tk.Frame(dlg, bg=C["bg"])
        btn_row.pack(fill="x", padx=20, pady=(16, 0))
        FlatButton(btn_row, "[ Save ]", on_save,
                   bg=C["green"], fg=C["crust"]).pack(side="left")
        FlatButton(btn_row, "[ Cancel ]", dlg.destroy,
                   bg=C["overlay"], fg=C["text"]).pack(side="left", padx=(8, 0))

    def _save_profile(self, name, server, group, port, protocol, username, password):
        """Save a profile to disk with DPAPI-encrypted credentials."""
        profile_dir = PROFILES_DIR / name
        profile_dir.mkdir(parents=True, exist_ok=True)

        # Save config
        cfg = {"Server": server, "Group": group, "Port": port, "Protocol": protocol}
        (profile_dir / "config.json").write_text(json.dumps(cfg, indent=2))

        # Save credentials (call PowerShell to encrypt with DPAPI)
        # Escape quotes in password for PowerShell
        safe_pw = password.replace('"', '`"')
        ps_cmd = (
            f'Add-Type -AssemblyName System.Security; '
            f'$bytes = [System.Text.Encoding]::UTF8.GetBytes("{safe_pw}"); '
            f'$enc = [System.Security.Cryptography.ProtectedData]::Protect('
            f'$bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser); '
            f'@{{Server="{server}"; Username="{username}"; Password=[Convert]::ToBase64String($enc)}} '
            f'| ConvertTo-Json'
        )
        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps_cmd],
                capture_output=True, text=True, timeout=10,
                startupinfo=_startupinfo(), creationflags=_CREATION_NO_WINDOW
            )
            if result.returncode == 0:
                (profile_dir / "credentials.xml").write_text(result.stdout.strip())
            else:
                self._save_cred_fallback(profile_dir, server, username, password)
        except Exception:
            self._save_cred_fallback(profile_dir, server, username, password)

        # Update index
        index = self._load_profiles()
        if name not in index:
            index.append(name)
            PROFILES_INDEX.write_text(json.dumps(index, indent=2))

        self._save_active_profile(name)
        self._current_profile = name
        self._refresh_profiles()
        self._log(f"Profile '{name}' added: {username}@{server}")

    @staticmethod
    def _save_cred_fallback(profile_dir, server, username, password):
        """Fallback: save credentials as base64 (less secure than DPAPI)."""
        import base64
        cred = {
            "Server": server,
            "Username": username,
            "Password": base64.b64encode(password.encode()).decode()
        }
        (profile_dir / "credentials.xml").write_text(json.dumps(cred, indent=2))

    def _remove_profile(self):
        display = self.profile_var.get()
        if not display:
            return
        name = self._internal_name(display)
        if not messagebox.askyesno("Confirm", f"Delete profile '{display}'?"):
            return

        # Remove directory
        profile_dir = PROFILES_DIR / name
        if profile_dir.exists():
            import shutil
            shutil.rmtree(profile_dir)

        # Update index
        index = self._load_profiles()
        if name in index:
            index.remove(name)
            PROFILES_INDEX.write_text(json.dumps(index, indent=2))

        # Clear active if needed
        if self._current_profile == name:
            self._current_profile = index[0] if index else None
            if self._current_profile:
                self._save_active_profile(self._current_profile)

        self._refresh_profiles()
        self._log(f"Profile '{name}' deleted")

    def _load_profile_cred(self, name):
        """Load credentials for a profile (username only, password masked)."""
        cred_path = PROFILES_DIR / name / "credentials.xml"
        if cred_path.exists():
            try:
                data = json.loads(cred_path.read_text())
                username = data.get("Username", "")
                has_pw = bool(data.get("Password", ""))
                return username, has_pw
            except (json.JSONDecodeError, OSError):
                pass
        return "", False

    def _show_configs(self):
        """Show a dialog listing all profiles with their full config and credentials."""
        profiles = self._load_profiles()
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
                 font=("Segoe UI", 11, "bold"),
                 bg=C["bg"], fg=C["text"]).pack(anchor="w", padx=20, pady=(14, 6))

        import tkinter.scrolledtext as st_cfg
        text_area = st_cfg.ScrolledText(
            dlg, bg=C["surface"], fg=C["text"],
            font=("Cascadia Code", 9), relief="flat", wrap="word",
            insertbackground=C["text"], selectbackground=C["blue"],
            selectforeground=C["crust"], bd=0, padx=10, pady=8
        )
        text_area.pack(fill="both", expand=True, padx=20, pady=(0, 12))

        active = self._load_active_profile()
        for name in profiles:
            cfg = self._load_profile_config(name)
            username, has_pw = self._load_profile_cred(name)
            display = self._display_name(name)
            marker = " *" if name == active else "  "
            text_area.insert("end", f"{marker}{display}\n", "name")
            text_area.insert("end", f"    NetID:    {username or '-'}\n")
            text_area.insert("end", f"    Password: {'(saved)' if has_pw else '(none)'}\n")
            if cfg:
                text_area.insert("end", f"    Server:   {cfg.get('Server', '-')}\n")
                text_area.insert("end", f"    Port:     {cfg.get('Port', '-')}\n")
                text_area.insert("end", f"    Protocol: {cfg.get('Protocol', '-')}\n")
                text_area.insert("end", f"    Group:    {cfg.get('Group', '-')}\n")
            else:
                text_area.insert("end", "    (no config found)\n")
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

    def _run_vpn_cmd(self, args, timeout=120):
        """Run vpn-auto-connect.ps1 with given args in a thread."""
        def worker():
            try:
                cmd = [
                    "powershell", "-ExecutionPolicy", "Bypass",
                    "-File", str(VPN_SCRIPT)
                ] + args
                self.root.after(0, self._log, f"[..] Running: vpn-auto-connect.ps1 {' '.join(args)}")
                result = subprocess.run(
                    cmd, capture_output=True, text=True, timeout=timeout,
                    startupinfo=_startupinfo()
                )
                output = result.stdout + result.stderr
                if output.strip():
                    for line in output.strip().split("\n"):
                        if line.strip():
                            self.root.after(0, self._log, line.strip())
                else:
                    self.root.after(0, self._log, f"[!!] No output (exit code: {result.returncode})")

                # Detect authentication failures
                auth_fail = any(kw in output for kw in [
                    "Login denied", "Authentication failed", "认证失败",
                    "Login failed", "Access denied", "auth failed"
                ])
                if auth_fail:
                    self.root.after(0, lambda: messagebox.showerror(
                        "Authentication Failed",
                        "Login denied. Please check your username and password.\n\n"
                        "If using DKU VPN, verify your NetID and password are correct."
                    ))

                self.root.after(0, self._refresh_status)
            except subprocess.TimeoutExpired:
                self.root.after(0, self._log, "[!!] Connection timed out")
            except Exception as e:
                self.root.after(0, self._log, f"[!!] Error: {e}")
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
        self._log(f"Connecting... (DUO: {method})")
        self._run_vpn_cmd(["-Connect", "-DuoMethod", method], timeout=180)

    def _disconnect(self):
        self._log("Disconnecting...")
        self._run_vpn_cmd(["-Disconnect"], timeout=30)

    def _refresh_status(self):
        """Check VPN status by looking for 10.x.x.x IP."""
        def worker():
            try:
                result = subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     "Get-NetAdapter | Where-Object Status -eq Up | "
                     "Get-NetIPAddress -ErrorAction SilentlyContinue | "
                     "Where-Object IPAddress -match '^10\\.' | "
                     "Select-Object -First 1 -ExpandProperty IPAddress"],
                    capture_output=True, text=True, timeout=10,
                    startupinfo=_startupinfo(), creationflags=_CREATION_NO_WINDOW
                )
                ip = result.stdout.strip()
                if ip:
                    self.root.after(0, self._set_connected, ip)
                else:
                    self.root.after(0, self._set_disconnected)
            except Exception:
                self.root.after(0, self._set_disconnected)

        self.status_indicator.set_checking()
        self.status_label.config(text="Checking...", fg=C["yellow"])
        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def _set_connected(self, ip):
        self._connected = True
        self.status_indicator.set_connected()
        self.status_label.config(text="Connected", fg=C["green"])
        name = self.profile_var.get() or "(unknown)"
        self.info_label.config(text=f"Profile: {name}  |  IP: {ip}")

    def _set_disconnected(self):
        self._connected = False
        self.status_indicator.set_disconnected()
        self.status_label.config(text="Disconnected", fg=C["red"])
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

    # -- Log --

    def _log(self, msg):
        self.log_text.insert("end", msg + "\n")
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
