#!/usr/bin/env python3
"""
OpenTTS 3D Pipeline - GUI Version
=================================

Einfaches GUI für die Batch-Verarbeitung von Gemini-Bildern zu 3D-Modellen.

Doppelklick auf 'Start Pipeline.command' (Mac) oder 'start_pipeline.bat' (Windows)
"""

import os
import sys
import threading
from pathlib import Path

# GUI imports
try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox, scrolledtext
except ImportError:
    print("Tkinter nicht verfügbar. Bitte installiere es oder nutze pipeline.py direkt.")
    sys.exit(1)

# Import pipeline functions
try:
    from pipeline import HuggingFaceTrellis, remove_watermark_from_file, HAS_PIL
except ImportError:
    print("pipeline.py nicht gefunden. Bitte im gleichen Ordner ausführen.")
    sys.exit(1)


class PipelineGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("OpenTTS 3D Pipeline")
        self.root.geometry("800x600")

        # Variables
        self.selected_files = []
        self.hf_token = tk.StringVar()
        self.resolution = tk.StringVar(value="1024")
        self.decimation = tk.IntVar(value=300000)
        self.texture_size = tk.IntVar(value=2048)
        self.is_processing = False

        # Load saved token if exists
        self.token_file = Path(__file__).parent / ".hf_token"
        if self.token_file.exists():
            self.hf_token.set(self.token_file.read_text().strip())

        self.create_widgets()

    def create_widgets(self):
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        # === Token Section ===
        token_frame = ttk.LabelFrame(main_frame, text="HuggingFace Token", padding="5")
        token_frame.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))

        ttk.Entry(token_frame, textvariable=self.hf_token, width=50, show="*").grid(row=0, column=0, padx=5)
        ttk.Button(token_frame, text="Speichern", command=self.save_token).grid(row=0, column=1, padx=5)
        ttk.Label(token_frame, text="(Token von huggingface.co/settings/tokens)").grid(row=1, column=0, columnspan=2)

        # === File Selection ===
        file_frame = ttk.LabelFrame(main_frame, text="Bilder auswählen", padding="5")
        file_frame.grid(row=1, column=0, columnspan=2, sticky="nsew", pady=(0, 10))
        main_frame.rowconfigure(1, weight=1)

        # Listbox with scrollbar
        list_frame = ttk.Frame(file_frame)
        list_frame.grid(row=0, column=0, sticky="nsew")
        file_frame.columnconfigure(0, weight=1)
        file_frame.rowconfigure(0, weight=1)

        self.file_listbox = tk.Listbox(list_frame, selectmode=tk.EXTENDED, height=10)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.file_listbox.yview)
        self.file_listbox.configure(yscrollcommand=scrollbar.set)

        self.file_listbox.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        list_frame.columnconfigure(0, weight=1)
        list_frame.rowconfigure(0, weight=1)

        # Buttons
        btn_frame = ttk.Frame(file_frame)
        btn_frame.grid(row=1, column=0, pady=5)

        ttk.Button(btn_frame, text="Bilder hinzufügen...", command=self.add_files).grid(row=0, column=0, padx=5)
        ttk.Button(btn_frame, text="Ausgewählte entfernen", command=self.remove_selected).grid(row=0, column=1, padx=5)
        ttk.Button(btn_frame, text="Alle entfernen", command=self.clear_files).grid(row=0, column=2, padx=5)

        # === Settings ===
        settings_frame = ttk.LabelFrame(main_frame, text="Qualitätseinstellungen", padding="5")
        settings_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(0, 10))

        # Resolution
        ttk.Label(settings_frame, text="Auflösung:").grid(row=0, column=0, padx=5, sticky="e")
        res_combo = ttk.Combobox(settings_frame, textvariable=self.resolution,
                                  values=["512", "1024", "1536"], width=10, state="readonly")
        res_combo.grid(row=0, column=1, padx=5, sticky="w")

        # Decimation
        ttk.Label(settings_frame, text="Mesh-Detail:").grid(row=0, column=2, padx=5, sticky="e")
        dec_combo = ttk.Combobox(settings_frame, textvariable=self.decimation,
                                  values=[100000, 200000, 300000, 400000, 500000], width=10, state="readonly")
        dec_combo.grid(row=0, column=3, padx=5, sticky="w")

        # Texture size
        ttk.Label(settings_frame, text="Texturgröße:").grid(row=0, column=4, padx=5, sticky="e")
        tex_combo = ttk.Combobox(settings_frame, textvariable=self.texture_size,
                                  values=[1024, 2048, 4096], width=10, state="readonly")
        tex_combo.grid(row=0, column=5, padx=5, sticky="w")

        # === Progress & Log ===
        log_frame = ttk.LabelFrame(main_frame, text="Fortschritt", padding="5")
        log_frame.grid(row=3, column=0, columnspan=2, sticky="nsew", pady=(0, 10))
        main_frame.rowconfigure(3, weight=1)

        self.log_text = scrolledtext.ScrolledText(log_frame, height=10, state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)

        self.progress = ttk.Progressbar(log_frame, mode="determinate")
        self.progress.grid(row=1, column=0, sticky="ew", pady=(5, 0))

        # === Start Button ===
        self.start_btn = ttk.Button(main_frame, text="🚀 Pipeline starten", command=self.start_pipeline)
        self.start_btn.grid(row=4, column=0, columnspan=2, pady=10)

    def save_token(self):
        token = self.hf_token.get().strip()
        if token:
            self.token_file.write_text(token)
            self.log("Token gespeichert.")
        else:
            self.log("Kein Token eingegeben.")

    def add_files(self):
        files = filedialog.askopenfilenames(
            title="Bilder auswählen",
            filetypes=[
                ("Bilder", "*.png *.jpg *.jpeg *.webp"),
                ("PNG", "*.png"),
                ("JPEG", "*.jpg *.jpeg"),
                ("Alle Dateien", "*.*")
            ]
        )
        for f in files:
            if f not in self.selected_files:
                self.selected_files.append(f)
                self.file_listbox.insert(tk.END, Path(f).name)
        self.log(f"{len(files)} Bild(er) hinzugefügt. Gesamt: {len(self.selected_files)}")

    def remove_selected(self):
        selected = list(self.file_listbox.curselection())
        selected.reverse()  # Remove from end to avoid index shifting
        for i in selected:
            self.file_listbox.delete(i)
            del self.selected_files[i]
        self.log(f"{len(selected)} Bild(er) entfernt.")

    def clear_files(self):
        self.file_listbox.delete(0, tk.END)
        self.selected_files = []
        self.log("Alle Bilder entfernt.")

    def log(self, message):
        self.log_text.configure(state="normal")
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state="disabled")
        self.root.update()

    def start_pipeline(self):
        if self.is_processing:
            return

        if not self.selected_files:
            messagebox.showwarning("Keine Bilder", "Bitte wähle zuerst Bilder aus.")
            return

        token = self.hf_token.get().strip()
        if not token:
            messagebox.showwarning("Kein Token", "Bitte gib deinen HuggingFace Token ein.")
            return

        # Start processing in thread
        self.is_processing = True
        self.start_btn.configure(state="disabled")
        thread = threading.Thread(target=self.process_files, daemon=True)
        thread.start()

    def process_files(self):
        try:
            token = self.hf_token.get().strip()
            resolution = self.resolution.get()
            decimation = self.decimation.get()
            texture_size = self.texture_size.get()

            self.log(f"\n{'='*50}")
            self.log(f"Starte Pipeline für {len(self.selected_files)} Bild(er)")
            self.log(f"Auflösung: {resolution}, Mesh: {decimation}, Textur: {texture_size}")
            self.log(f"{'='*50}\n")

            # Initialize TRELLIS
            self.log("Verbinde mit TRELLIS.2...")
            trellis = HuggingFaceTrellis(
                hf_token=token,
                resolution=resolution,
                decimation=decimation,
                texture_size=texture_size,
                preprocess=False  # We handle watermark removal ourselves
            )
            self.log("Verbunden!\n")

            # Process each file
            total = len(self.selected_files)
            success = 0
            failed = 0

            for i, filepath in enumerate(self.selected_files):
                self.progress["value"] = (i / total) * 100
                self.root.update()

                path = Path(filepath)
                self.log(f"[{i+1}/{total}] Verarbeite: {path.name}")

                try:
                    # Remove watermark
                    self.log("   Entferne Wasserzeichen...")
                    clean_path = remove_watermark_from_file(path)

                    # Generate 3D
                    self.log("   Generiere 3D-Modell (1-2 Minuten)...")
                    output_dir = path.parent
                    result = trellis.generate(clean_path, output_dir)

                    if result:
                        self.log(f"   ✅ Fertig: {result.name}\n")
                        success += 1
                    else:
                        self.log(f"   ❌ Fehlgeschlagen\n")
                        failed += 1

                except Exception as e:
                    self.log(f"   ❌ Fehler: {e}\n")
                    failed += 1

            self.progress["value"] = 100
            self.log(f"\n{'='*50}")
            self.log(f"FERTIG!")
            self.log(f"✅ Erfolgreich: {success}/{total}")
            self.log(f"❌ Fehlgeschlagen: {failed}/{total}")
            self.log(f"{'='*50}\n")

            # Show completion message
            self.root.after(0, lambda: messagebox.showinfo(
                "Fertig!",
                f"Pipeline abgeschlossen!\n\n✅ Erfolgreich: {success}\n❌ Fehlgeschlagen: {failed}"
            ))

        except Exception as e:
            self.log(f"\n❌ Kritischer Fehler: {e}")
            self.root.after(0, lambda: messagebox.showerror("Fehler", str(e)))

        finally:
            self.is_processing = False
            self.root.after(0, lambda: self.start_btn.configure(state="normal"))


def main():
    root = tk.Tk()
    app = PipelineGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
