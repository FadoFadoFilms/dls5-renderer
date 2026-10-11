"""FadoEXR Pipeline Manager (Windows-friendly Python/Tkinter desktop frontend)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

import pipeline_core as core


class ManagerWindow:
    def __init__(self, root):
        self.root = root
        self.root.title('FadoEXR Pipeline Manager - experimental v0.3')
        self.root.geometry('930x780')
        self.settings = core.Settings.load()
        self.events = queue.Queue()
        self.working = False
        self.seen = set()
        self.fields = {
            key: tk.StringVar(value=getattr(self.settings, key))
            for key in ('film_project', 'import_project', 'capture_root', 'player_root', 'selected_shot')
        }
        self.auto = tk.BooleanVar(value=self.settings.auto_handoff)
        self.fps = tk.IntVar(value=self.settings.fps)
        self._layout()
        root.after(150, self._poll_events)
        root.after(4000, self._poll_shots)
        self.log('Ready. Select both Unity project roots and save settings. All file updates are opt-in.')
        self.log('Renderer downloads are third-party community binaries and require explicit approval.')

    def _layout(self):
        # Scrollable layout: Windows DPI scaling can make this dashboard taller
        # than a laptop display. Keep the status line pinned beneath the canvas.
        shell = ttk.Frame(self.root)
        shell.pack(fill='both', expand=True)
        canvas = tk.Canvas(shell, highlightthickness=0)
        scroll = ttk.Scrollbar(shell, orient='vertical', command=canvas.yview)
        canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        canvas.pack(side='left', fill='both', expand=True)
        outer = ttk.Frame(canvas, padding=12)
        canvas_window = canvas.create_window((0, 0), window=outer, anchor='nw')
        outer.bind('<Configure>', lambda _event:canvas.configure(scrollregion=canvas.bbox('all')))
        canvas.bind('<Configure>', lambda event:canvas.itemconfigure(canvas_window, width=event.width))
        canvas.bind('<MouseWheel>', lambda event:canvas.yview_scroll(-int(event.delta / 120), 'units'))
        canvas.bind('<Button-4>', lambda _event:canvas.yview_scroll(-1, 'units'))
        canvas.bind('<Button-5>', lambda _event:canvas.yview_scroll(1, 'units'))
        ttk.Label(outer, text='FadoEXR  |  Pipeline Manager', font=('Segoe UI', 17, 'bold')).pack(anchor='w')
        ttk.Label(outer, text='Unity Export  ->  EXR/FFV1  ->  DLSS Player  ->  Unity Import',
                  foreground='#526274').pack(anchor='w', pady=(2, 12))
        paths = ttk.LabelFrame(outer, text='1. Workspace paths (Unity projects remain separate Git repositories)', padding=8)
        paths.pack(fill='x', pady=4)
        for row, (key, label, chooser) in enumerate([
            ('film_project', 'Film Unity project', True),
            ('import_project', 'EXR Renderer Unity project', True),
            ('capture_root', 'Unity capture output root', True),
            ('player_root', 'Managed DLSS player directory', True),
            ('selected_shot', 'Selected captured shot', True),
        ]):
            ttk.Label(paths, text=label, width=27).grid(row=row, column=0, sticky='w', padx=4, pady=3)
            ttk.Entry(paths, textvariable=self.fields[key]).grid(row=row, column=1, sticky='ew', padx=3)
            ttk.Button(paths, text='Browse', command=lambda k=key:self._browse(k)).grid(row=row, column=2, padx=4)
        paths.columnconfigure(1, weight=1)
        line = ttk.Frame(paths)
        line.grid(row=5, column=0, columnspan=3, sticky='ew', pady=5)
        ttk.Button(line, text='Save paths', command=self._save).pack(side='left', padx=4)
        ttk.Label(line, text='Shot capture is performed inside Unity; this app handles updates and handoffs.').pack(side='left', padx=7)

        unity = ttk.LabelFrame(outer, text='2. Install / update scripts in your Unity projects', padding=8)
        unity.pack(fill='x', pady=5)
        for text, op in [('Preview exporter changes', 'preview-export'),
                         ('Update film exporter', 'install-export'),
                         ('Preview importer changes', 'preview-import'),
                         ('Update EXR importer', 'install-import')]:
            ttk.Button(unity, text=text, command=lambda o=op:self._install_action(o)).pack(side='left', padx=4, pady=3)
        ttk.Label(outer, text='Changes affect only Assets/FadoEXR; source files and user .meta files are backed up/preserved.',
                  foreground='#526274').pack(anchor='w', pady=(0, 5))

        renderer = ttk.LabelFrame(outer, text='3. Latest player and shot processing', padding=8)
        renderer.pack(fill='x', pady=5)
        top = ttk.Frame(renderer)
        top.pack(fill='x')
        ttk.Button(top, text='Download / update renderer', command=self._update_player).pack(side='left', padx=4, pady=3)
        ttk.Button(top, text='Open DLSS Player', command=self._open_player).pack(side='left', padx=4, pady=3)
        ttk.Label(top, text='FPS:').pack(side='left', padx=(14, 3))
        ttk.Spinbox(top, textvariable=self.fps, from_=1, to=240, width=5).pack(side='left')
        bottom = ttk.Frame(renderer)
        bottom.pack(fill='x')
        ttk.Button(bottom, text='EXR -> lossless player video', command=self._convert).pack(side='left', padx=4, pady=3)
        ttk.Button(bottom, text='Run DLSS + stage result', command=self._render).pack(side='left', padx=4, pady=3)
        ttk.Button(bottom, text='Import processed video manually', command=self._manual_frames).pack(side='left', padx=4, pady=3)

        staging = ttk.LabelFrame(outer, text='4. Shot handoff to Unity EXR Renderer', padding=8)
        staging.pack(fill='x', pady=5)
        ttk.Checkbutton(staging, text='Automatically stage grade data when Unity finishes a capture',
                        variable=self.auto, command=self._save).pack(anchor='w', padx=4, pady=2)
        row = ttk.Frame(staging)
        row.pack(fill='x', pady=2)
        ttk.Button(row, text='Stage selected shot now', command=self._handoff).pack(side='left', padx=4)
        ttk.Button(row, text='Open importer inbox', command=self._open_inbox).pack(side='left', padx=4)
        ttk.Label(staging, text='Grade JSON is copied outside Assets to .fadoexr-inbox; raw EXRs are never duplicated by this step.',
                  foreground='#526274').pack(anchor='w', padx=4, pady=4)

        log_frame = ttk.LabelFrame(outer, text='Status and diagnostics', padding=8)
        log_frame.pack(fill='both', expand=True, pady=5)
        self.output = scrolledtext.ScrolledText(log_frame, height=12, wrap='word', state='disabled', font=('Consolas', 9))
        self.output.pack(fill='both', expand=True)
        self.status = tk.StringVar(value='Idle')
        ttk.Label(self.root, textvariable=self.status, padding=(12, 3)).pack(anchor='w')

    def log(self, message):
        self.output.configure(state='normal')
        self.output.insert('end', str(message).rstrip() + '\n')
        self.output.see('end')
        self.output.configure(state='disabled')

    def _poll_events(self):
        try:
            while True:
                kind, value = self.events.get_nowait()
                if kind == 'log':
                    self.log(value)
                elif kind == 'error':
                    self.working = False
                    self.status.set('Failed: ' + str(value))
                    self.log('ERROR: ' + str(value))
                    messagebox.showerror('FadoEXR pipeline error', str(value))
                elif kind == 'selected_shot':
                    self.fields['selected_shot'].set(value)
                    self.settings.selected_shot = value
                    self.settings.save()
                elif kind == 'done':
                    self.working = False
                    self.status.set('Finished')
                    self.log('DONE: ' + str(value))
        except queue.Empty:
            pass
        self.root.after(150, self._poll_events)

    def _worker(self, title, fn):
        if self.working:
            messagebox.showinfo('FadoEXR', 'Another operation is still running.')
            return
        self.working = True
        self.status.set(title + '...')
        self.log('START: ' + title)
        def thread_fn():
            try:
                message = fn()
                self.events.put(('done', message))
            except Exception as ex:
                self.events.put(('error', str(ex)))
        threading.Thread(target=thread_fn, daemon=True).start()

    def _browse(self, key):
        old = self.fields[key].get()
        new = filedialog.askdirectory(title=key.replace('_', ' ').title(), initialdir=old if Path(old).is_dir() else None)
        if new:
            self.fields[key].set(new)
            self._save()

    def _save(self):
        for k, var in self.fields.items():
            setattr(self.settings, k, var.get().strip())
        self.settings.auto_handoff = self.auto.get()
        try:
            if self.settings.film_project and self.settings.import_project:
                if Path(self.settings.film_project).expanduser().resolve() == Path(self.settings.import_project).expanduser().resolve():
                    raise ValueError('Film and import paths must be two different Unity projects.')
            self.settings.fps = int(self.fps.get())
            if not 1 <= self.settings.fps <= 240:
                raise ValueError('FPS must be between 1 and 240')
            self.settings.save()
        except (ValueError, OSError) as e:
            messagebox.showerror('Settings', str(e))
            return False
        return True

    def _install_action(self, op):
        if not self._save():
            return
        role = 'export' if op.endswith('export') else 'import'
        target = self.settings.film_project if role == 'export' else self.settings.import_project
        try:
            plan = core.inspect_project(role, target)
        except Exception as e:
            messagebox.showerror('Unity project', str(e))
            return
        msg = (f'{role.upper()} in {target}\n\n'
               f'{len(plan["added"])} new source files\n'
               f'{len(plan["changed"])} changed files\n'
               f'{len(plan["same"])} unchanged files\n'
               f'{len(plan["preserved_meta"])} existing .meta GUIDs protected\n')
        if op.startswith('preview'):
            self.log(msg + ('Changed: ' + ', '.join(plan['changed']) if plan['changed'] else ''))
            messagebox.showinfo('Update preview', msg)
            return
        if not messagebox.askyesno('Update Unity files', msg + '\nBack up your scene and save Unity first. '
                                   'An external backup of existing Assets/FadoEXR will be created. Continue?'):
            return
        self._worker('Updating Unity ' + role, lambda: json.dumps(core.install_unity(role, target), indent=2))

    def _run(self, cmd):
        self.events.put(('log', 'Running: ' + subprocess.list2cmdline(cmd)))
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, errors='replace', bufsize=1)
        assert process.stdout is not None
        for line in process.stdout:
            self.events.put(('log', line.rstrip()))
        rc = process.wait()
        if rc:
            raise RuntimeError('Command returned exit code ' + str(rc))

    def _update_player(self):
        if not self._save():
            return
        if not messagebox.askyesno('Community renderer download',
                                   'Download and install the latest COMPLETE third-party DLSS video player '
                                   '(hundreds of MB, experimental/unsigned) into the selected player folder? '
                                   'The existing runtime is backed up and the upstream verifier must pass.'):
            return
        root = self.settings.player_root
        self._worker('Downloading/verifying DLSS renderer', lambda: self._update_command(root))

    def _update_command(self, folder):
        self._run(core.player_update_command(folder))
        return 'Renderer updater finished; see update-logs for the exact version and verification.'

    def _open_player(self):
        if not self._save():
            return
        if sys.platform != 'win32':
            messagebox.showerror('Unavailable', 'The neural renderer requires Windows.')
            return
        path = Path(self.settings.player_root).expanduser() / 'upstream' / 'DLSSVideoPlayer.exe'
        if not path.is_file():
            messagebox.showerror('Renderer missing', 'Download the complete renderer first. Expected: ' + str(path))
            return
        try:
            subprocess.Popen([str(path)], cwd=str(path.parent))
            self.log('Launched: ' + str(path))
        except OSError as e:
            messagebox.showerror('Launch failure', str(e))

    def _selected(self):
        if not self._save():
            raise ValueError('Correct FPS and settings first')
        if not self.settings.selected_shot:
            raise ValueError('Choose a captured shot folder first.')
        return self.settings.selected_shot

    def _handoff(self):
        try:
            shot = self._selected()
            importer = self.settings.import_project
        except ValueError as e:
            messagebox.showerror('Shot', str(e))
            return
        self._worker('Staging captured shot', lambda: 'Shot staged: ' + json.dumps(
            core.handoff_capture(shot, importer), indent=2))

    def _convert(self):
        try:
            shot = self._selected()
            command = core.video_conversion_command(shot, self.settings.fps)
        except (ValueError, OSError) as e:
            messagebox.showerror('Conversion', str(e))
            return
        self._worker('Converting EXRs to FFV1', lambda: self._complete_conversion(command))

    def _complete_conversion(self, cmd):
        self._run(cmd)
        return 'Lossless FFV1 created in shot/Player_Input. Verify the colour transform before DLSS.'

    def _render(self):
        try:
            shot = self._selected()
            cmd = core.player_render_command(self.settings.player_root, shot, self.settings.fps)
            core.project_root(self.settings.import_project)
        except (ValueError, OSError, RuntimeError) as e:
            messagebox.showerror('Renderer', str(e))
            return
        if not messagebox.askyesno('Experimental GPU render',
                                   'Run the experimental DLSS player on this shot? This can take a long time '
                                   'and may stress a 6 GB GPU. A verified result will be converted and staged '
                                   'into the importer inbox. Continue?'):
            return
        self._worker('Rendering and staging result', lambda: self._render_and_stage(cmd, shot, self.settings.import_project))

    def _render_and_stage(self, cmd, shot, importer):
        self._run(cmd)
        rendered = core.latest_render_output(shot)
        if rendered is None:
            raise RuntimeError('No verified complete neural render found. Review Player_Output summary.json and logs; '
                               'no unverified output will be staged automatically.')
        self.events.put(('log', 'Verified full render found: ' + str(rendered)))
        frames = core.convert_processed_video(rendered, shot)
        info = core.handoff_processed_frames(shot, importer, frames)
        return 'Processed and staged ' + str(info['frameCount']) + ' frames in import project inbox: ' + info['jobId']

    def _manual_frames(self):
        try:
            shot = self._selected()
        except ValueError as e:
            messagebox.showerror('Shot', str(e))
            return
        video = filedialog.askopenfilename(title='Select player-rendered video',
                                           filetypes=[('Video files', '*.mkv *.mp4 *.mov')])
        if not video:
            return
        if not messagebox.askyesno('Manual video handoff',
                                   'This video was manually selected and has NOT been verified as a genuine '
                                   'neural render by the test harness. Convert it to PNG16 and stage it anyway?'):
            return
        self._worker('Converting and staging selected video',
                     lambda: self._manual_conversion(shot, video, self.settings.import_project))

    def _manual_conversion(self, shot, video, importer):
        frames = core.convert_processed_video(video, shot)
        info = core.handoff_processed_frames(shot, importer, frames)
        return 'Manually-selected video staged: ' + info['jobId']

    def _open_inbox(self):
        try:
            if not self._save():
                return
            inbox = core._inbox(self.settings.import_project)
            if sys.platform == 'win32':
                subprocess.Popen(['explorer.exe', str(inbox)])
            elif sys.platform == 'darwin':
                subprocess.Popen(['open', str(inbox)])
            else:
                subprocess.Popen(['xdg-open', str(inbox)])
        except Exception as e:
            messagebox.showerror('Inbox', str(e))

    def _poll_shots(self):
        if self.auto.get() and self.settings.import_project and self.settings.capture_root:
            # Keep watcher non-blocking. It never runs when a GUI foreground task runs.
            if not self.working:
                try:
                    shots = core.completed_shots(self.settings.capture_root)
                    # Only the most recently completed shot; don't replay all historical
                    # captures and overwrite latest.json with an older shot.
                    if shots and str(shots[-1]) not in self.seen:
                        shot = shots[-1]
                        def run():
                            result = core.handoff_capture(shot, self.settings.import_project)
                            self.seen.add(str(shot))
                            self.events.put(('selected_shot', str(shot)))
                            self.events.put(('log', 'Auto-staged: ' + result['shotName'] +
                                             '. In Unity importer, choose Load Latest Pipeline Handoff.'))
                            return 'Auto handoff finished' 
                        self._worker('Auto staging ' + shot.name, run)
                except Exception as e:
                    self.events.put(('log', 'Watch paused: ' + str(e)))
        self.root.after(4500, self._poll_shots)


def cli(args):
    if args.command == 'preview':
        print(json.dumps(core.inspect_project(args.role, args.project), indent=2))
    elif args.command == 'install':
        print(json.dumps(core.install_unity(args.role, args.project), indent=2))
    elif args.command == 'handoff':
        print(json.dumps(core.handoff_capture(args.shot, args.import_project), indent=2))
    elif args.command == 'send-frames':
        print(json.dumps(core.handoff_processed_frames(args.shot, args.import_project,
                                                       args.frames), indent=2))
    elif args.command == 'convert-exr':
        subprocess.run(core.video_conversion_command(args.shot, args.fps), check=True)
    elif args.command == 'update-player':
        subprocess.run(core.player_update_command(args.player_root), check=True)
    elif args.command == 'render':
        cmd = core.player_render_command(args.player_root, args.shot, args.fps)
        subprocess.run(cmd, check=True)
        result = core.latest_render_output(args.shot)
        if not result:
            raise RuntimeError('No verified neural render found; consult harness summary.json.')
        frames = core.convert_processed_video(result, args.shot)
        print(json.dumps(core.handoff_processed_frames(args.shot, args.import_project, frames), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command')
    for cmd in ('preview', 'install'):
        p = sub.add_parser(cmd)
        p.add_argument('role', choices=['export', 'import'])
        p.add_argument('project')
    p = sub.add_parser('handoff')
    p.add_argument('shot')
    p.add_argument('import_project')
    p = sub.add_parser('send-frames')
    p.add_argument('shot')
    p.add_argument('import_project')
    p.add_argument('frames')
    p = sub.add_parser('convert-exr')
    p.add_argument('shot')
    p.add_argument('--fps', type=int, default=24)
    p = sub.add_parser('update-player')
    p.add_argument('player_root')
    p = sub.add_parser('render')
    p.add_argument('shot')
    p.add_argument('import_project')
    p.add_argument('player_root')
    p.add_argument('--fps', type=int, default=24)
    args = parser.parse_args()
    if args.command:
        try:
            cli(args)
        except Exception as e:
            print('ERROR: ' + str(e), file=sys.stderr)
            sys.exit(2)
    else:
        root = tk.Tk()
        ttk.Style().theme_use('clam')
        ManagerWindow(root)
        root.mainloop()


if __name__ == '__main__':
    main()
