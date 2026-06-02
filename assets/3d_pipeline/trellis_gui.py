#!/usr/bin/env python3
"""
Niemandsland 3D Pipeline - GUI
==========================

Einfaches GUI zur Batch-Konvertierung von Bildern zu 3D-Modellen
mit Microsoft TRELLIS.2.

Qualitaet: Immer Maximum (1536px, 500k Polygone, 4K Textur)

Verwendung:
    python trellis_gui.py

Oder Doppelklick auf:
    - Windows: Start Pipeline.bat
    - macOS:   Start Pipeline.command
"""

import sys
import threading
from pathlib import Path

# GUI imports
try:
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox, scrolledtext
except ImportError:
    print("FEHLER: Tkinter nicht verfuegbar")
    print("        Unter Linux: sudo apt install python3-tk")
    sys.exit(1)

# Core imports
try:
    from trellis_core import (
        TrellisGenerator,
        find_images,
        load_token,
        save_token,
        RESOLUTION,
        DECIMATION,
        TEXTURE_SIZE,
        HAS_GRADIO
    )
except ImportError as e:
    print(f"FEHLER: trellis_core.py nicht gefunden: {e}")
    print("        Bitte im gleichen Ordner ausfuehren.")
    sys.exit(1)


class TrellisGUI:
    """Hauptfenster der 3D Pipeline."""

    def __init__(self, root):
        self.root = root
        self.root.title("Niemandsland 3D Pipeline - Trellis.2")
        self.root.geometry("700x550")
        self.root.minsize(600, 450)

        # Variablen
        self.hf_token = tk.StringVar()
        self.input_dir = tk.StringVar()
        self.output_dir = tk.StringVar()
        self.image_count = tk.StringVar(value="Kein Ordner ausgewaehlt")
        self.is_processing = False
        self.found_images = []

        # Token laden
        saved_token = load_token()
        if saved_token:
            self.hf_token.set(saved_token)

        self.create_widgets()

    def create_widgets(self):
        """Erstellt alle GUI-Elemente."""

        # Hauptframe mit Padding
        main = ttk.Frame(self.root, padding="15")
        main.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        row = 0

        # === TITEL ===
        title = ttk.Label(main, text="Bilder zu 3D-Modellen konvertieren",
                         font=("", 14, "bold"))
        title.grid(row=row, column=0, columnspan=3, pady=(0, 15))
        row += 1

        # === TOKEN ===
        token_frame = ttk.LabelFrame(main, text="HuggingFace Token", padding="10")
        token_frame.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(0, 10))

        ttk.Entry(token_frame, textvariable=self.hf_token, width=50, show="*"
                 ).grid(row=0, column=0, padx=(0, 10), sticky="ew")
        ttk.Button(token_frame, text="Speichern", command=self.save_token_click
                  ).grid(row=0, column=1)
        token_frame.columnconfigure(0, weight=1)

        ttk.Label(token_frame, text="Token von: huggingface.co/settings/tokens",
                 foreground="gray").grid(row=1, column=0, columnspan=2, sticky="w", pady=(5, 0))
        row += 1

        # === INPUT ORDNER ===
        input_frame = ttk.LabelFrame(main, text="Bilder-Ordner (Eingabe)", padding="10")
        input_frame.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(0, 10))

        ttk.Entry(input_frame, textvariable=self.input_dir, width=50
                 ).grid(row=0, column=0, padx=(0, 10), sticky="ew")
        ttk.Button(input_frame, text="Ordner waehlen...", command=self.select_input_dir
                  ).grid(row=0, column=1)
        input_frame.columnconfigure(0, weight=1)

        self.count_label = ttk.Label(input_frame, textvariable=self.image_count,
                                     foreground="blue")
        self.count_label.grid(row=1, column=0, columnspan=2, sticky="w", pady=(5, 0))
        row += 1

        # === OUTPUT ORDNER ===
        output_frame = ttk.LabelFrame(main, text="Output-Ordner (GLB-Dateien)", padding="10")
        output_frame.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(0, 10))

        ttk.Entry(output_frame, textvariable=self.output_dir, width=50
                 ).grid(row=0, column=0, padx=(0, 10), sticky="ew")
        ttk.Button(output_frame, text="Ordner waehlen...", command=self.select_output_dir
                  ).grid(row=0, column=1)
        ttk.Button(output_frame, text="= Input", command=self.set_output_same_as_input
                  ).grid(row=0, column=2, padx=(5, 0))
        output_frame.columnconfigure(0, weight=1)

        ttk.Label(output_frame, text="GLB-Dateien erhalten gleichen Namen wie Bilder",
                 foreground="gray").grid(row=1, column=0, columnspan=3, sticky="w", pady=(5, 0))
        row += 1

        # === QUALITAET INFO ===
        quality_frame = ttk.LabelFrame(main, text="Qualitaet", padding="10")
        quality_frame.grid(row=row, column=0, columnspan=3, sticky="ew", pady=(0, 10))

        quality_text = f"Maximum: {RESOLUTION}px Aufloesung, {DECIMATION:,} Polygone, {TEXTURE_SIZE}px Textur"
        ttk.Label(quality_frame, text=quality_text, font=("", 10, "bold"),
                 foreground="green").grid(row=0, column=0)
        row += 1

        # === LOG ===
        log_frame = ttk.LabelFrame(main, text="Fortschritt", padding="10")
        log_frame.grid(row=row, column=0, columnspan=3, sticky="nsew", pady=(0, 10))
        main.rowconfigure(row, weight=1)

        self.log_text = scrolledtext.ScrolledText(log_frame, height=10, state="disabled",
                                                   font=("Consolas", 9))
        self.log_text.grid(row=0, column=0, sticky="nsew")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)

        # Progressbar
        self.progress = ttk.Progressbar(log_frame, mode="determinate")
        self.progress.grid(row=1, column=0, sticky="ew", pady=(10, 0))

        self.progress_label = ttk.Label(log_frame, text="")
        self.progress_label.grid(row=2, column=0, sticky="w")
        row += 1

        # === START BUTTON ===
        self.start_btn = ttk.Button(main, text="Konvertierung starten",
                                    command=self.start_conversion)
        self.start_btn.grid(row=row, column=0, columnspan=3, pady=(5, 0), ipady=10)

        # Spalten konfigurieren
        main.columnconfigure(0, weight=1)

    def log(self, message: str):
        """Schreibt eine Nachricht ins Log (thread-safe)."""
        def _log():
            self.log_text.configure(state="normal")
            self.log_text.insert(tk.END, message + "\n")
            self.log_text.see(tk.END)
            self.log_text.configure(state="disabled")
            self.log_text.update_idletasks()
            self.root.update_idletasks()

        # Wenn aus Thread aufgerufen, nach Main-Thread dispatchen
        try:
            self.root.after(0, _log)
            self.root.update()
        except Exception:
            # Fallback wenn tkinter Probleme macht
            print(message)

    def save_token_click(self):
        """Speichert den Token."""
        token = self.hf_token.get().strip()
        if token:
            save_token(token)
            self.log("Token gespeichert.")
        else:
            messagebox.showwarning("Kein Token", "Bitte Token eingeben.")

    def select_input_dir(self):
        """Oeffnet Dialog zur Ordnerauswahl."""
        directory = filedialog.askdirectory(title="Bilder-Ordner auswaehlen")
        if directory:
            self.input_dir.set(directory)
            self.scan_images()

            # Output automatisch setzen wenn leer
            if not self.output_dir.get():
                self.output_dir.set(directory)

    def select_output_dir(self):
        """Oeffnet Dialog zur Output-Ordnerauswahl."""
        directory = filedialog.askdirectory(title="Output-Ordner auswaehlen")
        if directory:
            self.output_dir.set(directory)

    def set_output_same_as_input(self):
        """Setzt Output = Input."""
        if self.input_dir.get():
            self.output_dir.set(self.input_dir.get())

    def scan_images(self):
        """Scannt den Eingabeordner nach Bildern."""
        input_path = Path(self.input_dir.get())
        if input_path.exists():
            self.found_images = find_images(input_path)
            count = len(self.found_images)
            if count > 0:
                self.image_count.set(f"Gefunden: {count} Bild(er)")
                self.count_label.configure(foreground="green")
            else:
                self.image_count.set("Keine Bilder gefunden (PNG, JPG, WEBP)")
                self.count_label.configure(foreground="red")
        else:
            self.image_count.set("Ordner existiert nicht")
            self.count_label.configure(foreground="red")
            self.found_images = []

    def start_conversion(self):
        """Startet die Konvertierung."""
        if self.is_processing:
            return

        # Validierung
        if not self.hf_token.get().strip():
            messagebox.showwarning("Kein Token", "Bitte HuggingFace Token eingeben.")
            return

        if not self.input_dir.get():
            messagebox.showwarning("Kein Ordner", "Bitte Bilder-Ordner auswaehlen.")
            return

        self.scan_images()
        if not self.found_images:
            messagebox.showwarning("Keine Bilder", "Keine Bilder im Ordner gefunden.")
            return

        if not self.output_dir.get():
            self.output_dir.set(self.input_dir.get())

        # Starten
        self.is_processing = True
        self.start_btn.configure(state="disabled")
        self.progress["value"] = 0

        thread = threading.Thread(target=self.process_images, daemon=True)
        thread.start()

    def process_images(self):
        """Verarbeitet alle Bilder (im Thread)."""
        try:
            token = self.hf_token.get().strip()
            output_path = Path(self.output_dir.get())

            total = len(self.found_images)
            self.log(f"\n{'='*50}")
            self.log(f"Starte Konvertierung von {total} Bild(ern)")
            self.log(f"Output: {output_path}")
            self.log(f"{'='*50}\n")

            # Generator initialisieren
            generator = TrellisGenerator(hf_token=token, log_callback=self.log)
            self.log("")

            success = 0
            failed = 0

            for i, image_path in enumerate(self.found_images):
                # Progress Update
                progress_pct = (i / total) * 100
                self.progress["value"] = progress_pct
                self.progress_label.configure(text=f"{i}/{total} ({progress_pct:.0f}%)")
                self.root.update()

                self.log(f"[{i+1}/{total}] {image_path.name}")

                result = generator.convert(image_path, output_path)

                if result:
                    success += 1
                else:
                    failed += 1

                self.log("")

            # Fertig
            self.progress["value"] = 100
            self.progress_label.configure(text=f"{total}/{total} (100%)")

            self.log(f"{'='*50}")
            self.log(f"FERTIG!")
            self.log(f"Erfolgreich: {success}/{total}")
            self.log(f"Fehlgeschlagen: {failed}/{total}")
            self.log(f"Output: {output_path}")
            self.log(f"{'='*50}")

            self.root.after(0, lambda: messagebox.showinfo(
                "Fertig!",
                f"Konvertierung abgeschlossen!\n\n"
                f"Erfolgreich: {success}\n"
                f"Fehlgeschlagen: {failed}\n\n"
                f"Output: {output_path}"
            ))

        except Exception as e:
            self.log(f"\nKRITISCHER FEHLER: {e}")
            import traceback
            self.log(traceback.format_exc())
            self.root.after(0, lambda: messagebox.showerror("Fehler", str(e)))

        finally:
            self.is_processing = False
            self.root.after(0, lambda: self.start_btn.configure(state="normal"))


def main():
    """Startet die Anwendung."""
    if not HAS_GRADIO:
        print("\nFEHLER: Abhaengigkeiten fehlen!")
        print("        pip install gradio_client Pillow")
        print("\nDruecke Enter zum Beenden...")
        input()
        sys.exit(1)

    root = tk.Tk()
    app = TrellisGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
