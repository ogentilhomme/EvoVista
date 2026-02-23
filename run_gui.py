#!/usr/bin/env python3
"""
GUI to select project, set parameters (blur, matcher, image set), see latest step,
and run the pipeline in a new terminal window for raw output and easy debugging.
"""
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
RUN_SH = ROOT / "run.sh"
# Dock/window icon: put your icon at resources/icon.png (e.g. 256×256 or 512×512 PNG)
ICON_PATH = ROOT / "resources" / "image.png"

# Artifacts that would be overwritten when starting from each step (only these are checked/archived)
ARTIFACTS_BY_FROM_STEP = {
    "video": ["images", "images_resized", "images_resized_filtered", "database.db", "sparse", "dense", "blur_histogram.png"],
    "images": ["images_resized", "images_resized_filtered", "database.db", "sparse", "dense", "blur_histogram.png"],
    "images_resized": ["images_resized_filtered", "database.db", "sparse", "dense", "blur_histogram.png"],
    "feature_extraction": ["database.db", "sparse", "dense"],
    "feature_matching": ["sparse", "dense"],
    "sparse_reconstruction": ["dense"],
    "dense_reconstruction": ["dense"],
}


def get_projects():
    if not DATA_DIR.is_dir():
        return []
    return sorted(
        d.name for d in DATA_DIR.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    )


def get_latest_step(project_dir: Path) -> str:
    project_dir = Path(project_dir)
    if not project_dir.is_dir():
        return "—"
    dense = project_dir / "dense"
    if dense.is_dir() and any((dense / d.name / "fused.ply").exists() for d in dense.iterdir() if d.is_dir()):
        return "dense_reconstruction"
    sparse = project_dir / "sparse"
    if sparse.is_dir() and any(sparse.iterdir()):
        return "sparse_reconstruction"
    if (project_dir / "database.db").is_file():
        return "feature_matching"
    if (project_dir / "images_resized").is_dir() and list((project_dir / "images_resized").glob("*.jpg")):
        return "images_resized"
    if (project_dir / "images").is_dir() and list((project_dir / "images").glob("*.jpg")):
        return "images"
    videos = list(project_dir.glob("*.mov")) + list(project_dir.glob("*.mp4"))
    if videos:
        return "video"
    return "—"


def has_existing_pipeline_data(project_dir: Path, from_step: str) -> bool:
    """True if any artifact that would be overwritten when starting from from_step exists."""
    project_dir = Path(project_dir)
    names = ARTIFACTS_BY_FROM_STEP.get(from_step, [])
    for name in names:
        p = project_dir / name
        if p.exists():
            if p.is_dir():
                if name in ("sparse", "dense") or list(p.glob("*")):
                    return True
            else:
                return True
    return False


def archive_project_data(project_dir: Path, from_step: str) -> Path:
    """Move only artifacts that would be overwritten (from from_step onward) into archive_YYYYMMDD_HHMMSS/."""
    project_dir = Path(project_dir)
    names = ARTIFACTS_BY_FROM_STEP.get(from_step, [])
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    archive_dir = project_dir / f"archive_{stamp}"
    archive_dir.mkdir(parents=True, exist_ok=True)
    for name in names:
        src = project_dir / name
        if not src.exists():
            continue
        dst = archive_dir / name
        if src.is_dir():
            src.rename(dst)
        else:
            src.rename(dst)
    return archive_dir


def build_pipeline_args(
    project: str,
    from_step: str,
    blur_threshold: str,
    matcher: str,
    use_image_set: str,
    skip_blur_if_plot: bool,
) -> list:
    """Build argv for run.sh (without 'bash')."""
    cmd = [
        str(RUN_SH), project,
        "--from-step", from_step,
        "--matcher", matcher,
        "--use-image-set", use_image_set,
    ]
    if blur_threshold.strip():
        try:
            float(blur_threshold.strip())
            cmd += ["--blur-threshold", blur_threshold.strip()]
        except ValueError:
            pass
    if skip_blur_if_plot:
        cmd += ["--skip-blur-if-plot"]
    return cmd


def run_pipeline_in_terminal(
    project: str,
    from_step: str,
    blur_threshold: str,
    matcher: str,
    use_image_set: str,
    skip_blur_if_plot: bool,
) -> tuple[bool, str]:
    """Open a new terminal and run the pipeline there. Returns (success, command_string)."""
    args = build_pipeline_args(
        project, from_step, blur_threshold, matcher, use_image_set, skip_blur_if_plot
    )
    # Shell command: cd to ROOT and run bash run.sh ...
    root_str = str(ROOT)
    run_sh = str(RUN_SH)
    cmd_parts = [f"bash {run_sh}", project, f"--from-step {from_step}", f"--matcher {matcher}", f"--use-image-set {use_image_set}"]
    if blur_threshold.strip():
        try:
            float(blur_threshold.strip())
            cmd_parts.append(f"--blur-threshold {blur_threshold.strip()}")
        except ValueError:
            pass
    if skip_blur_if_plot:
        cmd_parts.append("--skip-blur-if-plot")
    cmd_str = " ".join(cmd_parts)
    # Quote cd path if it contains spaces
    if " " in root_str:
        cd_cmd = f'cd "{root_str}" && {cmd_str}'
    else:
        cd_cmd = f"cd {root_str} && {cmd_str}"
    full_cmd = cd_cmd

    if sys.platform == "darwin":
        # macOS: open new Terminal window and run command
        escaped = full_cmd.replace("\\", "\\\\").replace('"', '\\"')
        script = f'tell application "Terminal" to do script "{escaped}"'
        try:
            subprocess.Popen(["osascript", "-e", script], start_new_session=True)
            return True, full_cmd
        except Exception as e:
            return False, str(e)
    elif sys.platform.startswith("linux"):
        # Linux: try gnome-terminal, then xterm
        try:
            subprocess.Popen(
                ["gnome-terminal", "--", "bash", "-c", full_cmd + "; exec bash"],
                start_new_session=True,
            )
            return True, full_cmd
        except FileNotFoundError:
            try:
                subprocess.Popen(["xterm", "-e", full_cmd + "; exec bash"], start_new_session=True)
                return True, full_cmd
            except FileNotFoundError:
                return False, "No terminal found (tried gnome-terminal, xterm)"
        except Exception as e:
            return False, str(e)
    else:
        # Windows: start cmd in new window
        try:
            subprocess.Popen(
                ["start", "cmd", "/k", f"cd /d {root_str} && bash {run_sh} {project} --from-step {from_step} --matcher {matcher} --use-image-set {use_image_set}"],
                shell=True,
                cwd=str(ROOT),
            )
            return True, full_cmd
        except Exception as e:
            return False, str(e)


def _set_app_icon(root):
    """Set window icon and, on macOS, the dock icon."""
    import sys
    if not ICON_PATH.is_file():
        return
    try:
        from tkinter import PhotoImage
        img = PhotoImage(file=str(ICON_PATH))
        root.iconphoto(True, img)  # window + task switcher
        root._icon_photo = img  # keep reference so icon is not garbage-collected
    except Exception:
        pass
    # macOS dock icon (requires: pip install pyobjc-framework-Cocoa)
    if sys.platform == "darwin":
        try:
            from AppKit import NSApplication, NSImage
            nsapp = NSApplication.sharedApplication()
            icon = NSImage.alloc().initWithContentsOfFile_(str(ICON_PATH))
            if icon is not None:
                nsapp.setApplicationIconImage_(icon)
        except Exception:
            pass


def main():
    import tkinter as tk
    from tkinter import ttk, scrolledtext, messagebox

    projects = get_projects()
    if not projects:
        projects = ["(no projects in data/)"]

    root = tk.Tk()
    _set_app_icon(root)
    root.title("EvoVista pipeline")
    root.geometry("680x520")
    root.minsize(520, 420)

    main_frame = ttk.Frame(root, padding=10)
    main_frame.pack(fill=tk.BOTH, expand=True)

    # Project
    ttk.Label(main_frame, text="Project:").grid(row=0, column=0, sticky=tk.W, pady=2)
    project_var = tk.StringVar(value=projects[0] if projects[0] != "(no projects in data/)" else "")
    project_combo = ttk.Combobox(main_frame, textvariable=project_var, values=projects, state="readonly", width=28)
    project_combo.grid(row=0, column=1, sticky=tk.EW, pady=2, padx=(8, 0))
    project_combo.bind("<<ComboboxSelected>>", lambda e: refresh_latest())

    # Latest step
    ttk.Label(main_frame, text="Latest step:").grid(row=1, column=0, sticky=tk.W, pady=2)
    latest_var = tk.StringVar(value="—")

    def refresh_latest():
        p = project_var.get().strip()
        if not p or p == "(no projects in data/)":
            latest_var.set("—")
            return
        latest_var.set(get_latest_step(DATA_DIR / p))

    latest_label = ttk.Label(main_frame, textvariable=latest_var)
    latest_label.grid(row=1, column=1, sticky=tk.W, pady=2, padx=(8, 0))
    ttk.Button(main_frame, text="Refresh", command=refresh_latest).grid(row=1, column=2, padx=(8, 0))
    refresh_latest()

    # Start from
    ttk.Label(main_frame, text="Start from:").grid(row=2, column=0, sticky=tk.W, pady=2)
    steps = [
        "video", "images", "images_resized",
        "feature_extraction", "feature_matching", "sparse_reconstruction", "dense_reconstruction",
    ]
    from_step_var = tk.StringVar(value="video")
    from_combo = ttk.Combobox(main_frame, textvariable=from_step_var, values=steps, state="readonly", width=28)
    from_combo.grid(row=2, column=1, sticky=tk.EW, pady=2, padx=(8, 0))

    # Blur threshold
    ttk.Label(main_frame, text="Blur threshold:").grid(row=3, column=0, sticky=tk.W, pady=2)
    blur_var = tk.StringVar(value="")
    blur_entry = ttk.Entry(main_frame, textvariable=blur_var, width=20)
    blur_entry.grid(row=3, column=1, sticky=tk.W, pady=2, padx=(8, 0))
    ttk.Label(main_frame, text="(N = create filtered folder with blur ≥ N)").grid(row=3, column=2, sticky=tk.W, padx=(8, 0))

    # Use image set (for COLMAP)
    ttk.Label(main_frame, text="Use image set:").grid(row=4, column=0, sticky=tk.W, pady=2)
    use_image_set_var = tk.StringVar(value="whole")
    imgset_frame = ttk.Frame(main_frame)
    imgset_frame.grid(row=4, column=1, sticky=tk.W, pady=2, padx=(8, 0))
    ttk.Radiobutton(imgset_frame, text="Whole (images_resized)", variable=use_image_set_var, value="whole").pack(side=tk.LEFT)
    ttk.Radiobutton(imgset_frame, text="Filtered", variable=use_image_set_var, value="filtered").pack(side=tk.LEFT, padx=(12, 0))

    # Skip blur if plot exists
    skip_blur_var = tk.BooleanVar(value=False)
    ttk.Checkbutton(main_frame, text="Skip blur step if plot already exists", variable=skip_blur_var).grid(row=5, column=1, sticky=tk.W, pady=2, padx=(8, 0))

    # Matcher
    ttk.Label(main_frame, text="Matcher:").grid(row=6, column=0, sticky=tk.W, pady=2)
    matcher_var = tk.StringVar(value="exhaustive")
    matcher_frame = ttk.Frame(main_frame)
    matcher_frame.grid(row=6, column=1, sticky=tk.W, pady=2, padx=(8, 0))
    ttk.Radiobutton(matcher_frame, text="Exhaustive", variable=matcher_var, value="exhaustive").pack(side=tk.LEFT)
    ttk.Radiobutton(matcher_frame, text="Sequential", variable=matcher_var, value="sequential").pack(side=tk.LEFT, padx=(12, 0))

    ttk.Label(main_frame, text="Output:").grid(row=7, column=0, sticky=tk.NW, pady=(8, 0))
    log_area = scrolledtext.ScrolledText(main_frame, height=14, width=72, state=tk.NORMAL, wrap=tk.WORD)
    log_area.grid(row=7, column=1, columnspan=2, sticky=tk.NSEW, pady=(4, 0), padx=(8, 0))

    def do_run():
        p = project_var.get().strip()
        if not p or p == "(no projects in data/)":
            messagebox.showerror("Error", "Select a project.")
            return
        if not RUN_SH.is_file():
            messagebox.showerror("Error", f"run.sh not found: {RUN_SH}")
            return

        proj_dir = DATA_DIR / p
        from_step = from_step_var.get()

        # Ask Overwrite / Archive / Cancel when artifacts that would be overwritten by this run exist
        if has_existing_pipeline_data(proj_dir, from_step):
            artifacts = ARTIFACTS_BY_FROM_STEP.get(from_step, [])
            choice = messagebox.askyesnocancel(
                "Existing data",
                f"Starting from «{from_step}» would overwrite: {', '.join(artifacts)}\n\n"
                "Yes = Archive those to a timestamped folder, then run\n"
                "No  = Overwrite and run\n"
                "Cancel = Do not run",
            )
            if choice is None:  # Cancel
                return
            if choice is True:  # Archive
                try:
                    archive_path = archive_project_data(proj_dir, from_step)
                    log_area.delete("1.0", tk.END)
                    log_area.insert(tk.END, f"Archived to:\n{archive_path}\n\n")
                    log_area.see(tk.END)
                except Exception as e:
                    messagebox.showerror("Archive failed", str(e))
                    return

        from_step = from_step_var.get()
        blur_threshold = blur_var.get()
        matcher = matcher_var.get()
        use_image_set = use_image_set_var.get()
        skip_blur = skip_blur_var.get()

        ok, result = run_pipeline_in_terminal(
            p, from_step, blur_threshold, matcher, use_image_set, skip_blur
        )
        if ok:
            log_area.delete("1.0", tk.END)
            log_area.insert(
                tk.END,
                f"Pipeline started in new terminal window.\n\n"
                f"Command (for copy/paste):\n{result}\n\n"
                f"Output is raw in the terminal. Use Ctrl+C there to stop.",
            )
            log_area.see(tk.END)
            refresh_latest()
        else:
            messagebox.showerror("Could not open terminal", result)

    btn_frame = ttk.Frame(main_frame)
    btn_frame.grid(row=8, column=1, sticky=tk.W, pady=(12, 4), padx=(8, 0))
    run_btn = ttk.Button(btn_frame, text="Run pipeline (in new terminal)", command=do_run)
    run_btn.pack(side=tk.LEFT)

    ttk.Label(
        main_frame,
        text="Output runs in a new terminal window — raw stdout/stderr for easier debugging.",
        font=("", 8),
        foreground="gray",
    ).grid(row=9, column=1, sticky=tk.W, pady=(0, 4), padx=(8, 0))

    main_frame.columnconfigure(1, weight=1)
    main_frame.rowconfigure(7, weight=1)
    root.columnconfigure(0, weight=1)
    root.rowconfigure(0, weight=1)

    # Bring window to front when it opens (works on macOS and others)
    def bring_to_front():
        root.lift()
        root.attributes("-topmost", True)
        root.after(100, lambda: root.attributes("-topmost", False))
        root.focus_force()
    root.after(1, bring_to_front)

    root.mainloop()


if __name__ == "__main__":
    main()
