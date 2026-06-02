# Niemandsland - Beispiele & Test-Dateien

Dieser Ordner enthält Beispieldateien und Test-Daten für Niemandsland.

---

## 📁 Inhalt

### Army Forge Listen
- `Custodian Brothers - AGF-VWeitIpxvQ_LO.json` - Beispiel OPR Army Forge Liste (Grimdark Future)
  - **System**: Grimdark Future
  - **Punkte**: 3000
  - **Einheiten**: 22 Modelle, 8 Aktivierungen
  - **Verwendung**: Test für OPR Import-Funktionalität

---

## 🎯 Verwendung

### Army Forge Import testen
1. Starte Niemandsland
2. Öffne das OPR Import-Menü
3. Wähle die JSON-Datei aus diesem Ordner
4. Import sollte die Einheiten spawnen

### Eigene Beispiele hinzufügen
- Speichere deine Test-Dateien hier
- Füge eine Beschreibung in dieser README hinzu
- Committe mit aussagekräftiger Nachricht

---

## 📝 Format-Referenzen

### Army Forge JSON
```json
{
  "id": "...",
  "list": {
    "name": "Army Name",
    "units": [...],
    "pointsLimit": 3000,
    "gameSystem": "gf"
  },
  "armyName": "Faction Name"
}
```

### WGS Format
```
72                    ← Tischbreite in Zoll
48                    ← Tischtiefe in Zoll
{size},{x},{y},{color},{angle},{imageId},{name}
...
```

Siehe [../docs/WGS_INTEGRATION.md](../docs/WGS_INTEGRATION.md) für Details.

---

## 🤝 Beiträge

Gerne kannst du weitere Beispiel-Listen hinzufügen:
- OPR Army Forge Listen
- WGS Spielzustände
- TTS Workshop URLs
- Custom Szenarios

**Wichtig**: Achte auf Lizenzen und teile nur eigene oder frei verfügbare Inhalte!

---

**Letzte Aktualisierung:** 2026-01-01
