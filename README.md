# Electron RTL Patcher

**Smart Hebrew / Arabic RTL support for any Electron desktop app on Windows.**
תמיכת RTL חכמה בעברית/ערבית לכל אפליקציית Electron על Windows.

One patcher, many apps — Claude Desktop, VS Code, Cursor, ChatGPT, Slack and more. Add your own in `apps.json`.

> Independent community accessibility tool by **Naor Hilel / הלל פתרונות**. Not affiliated with Anthropic, Microsoft, OpenAI, Slack, or any other vendor. MIT licensed.

---

## עברית

### מה זה עושה
הרבה אפליקציות דסקטופ בנויות על Electron (כרום + Node) — Claude Desktop, VS Code, Cursor, ChatGPT, Slack ועוד. רובן לא מטפלות נכון בעברית/ערבית, והטקסט יוצא הפוך או מיושר לא נכון.

הכלי הזה מזריק שכבת CSS+JS קטנה שמתקנת את זה **לפי אלגוריתם ה-bidi של יוניקוד**: כל פסקה מקבלת כיוון לפי התו החזק הראשון שלה — עברית/ערבית זורמות RTL, אנגלית וקוד נשארים LTR. הוא **לא משכתב את ה-DOM**, ולכן לא שובר אפליקציות מבוססות React.

### למה זה בטוח
- **גיבוי לפני כל שינוי** — כל קובץ שמשתנה נשמר ב-`%ProgramData%\ElectronRtlPatch\backups\`, ויש שחזור מלא.
- **אידמפוטנטי** — הרצה חוזרת לא מזריקה פעמיים (יש marker).
- **רק שני יעדי רשת**: GitHub (להורדה) ונקודת הקצה הרשמית של כל אפליקציה. אין טלמטריה, אין איסוף מידע.
- **קוד פתוח, ASCII בלבד בליבת ה-JS** — קל לקרוא ולבדוק.

### התקנה

**הדרך המומלצת (בטוחה):** להוריד את הריפו, לקרוא את `patch.ps1`, ואז להריץ:
```powershell
git clone https://github.com/naor1237-tech/electron-rtl-patcher.git
cd electron-rtl-patcher
powershell -ExecutionPolicy Bypass -File .\patch.ps1
```

**שורה אחת (רק אחרי שקראת את הקוד):**
```powershell
irm https://raw.githubusercontent.com/naor1237-tech/electron-rtl-patcher/main/install.ps1 | iex
```

ייפתח תפריט: בוחרים אפליקציה (או `A` לכל מה שמותקן), והכלי מתקן. **חובה לסגור ולפתוח מחדש את האפליקציה** כדי לראות את השינוי.

### דרישות
- Windows 10/11
- **Node.js** מותקן (הכלי משתמש ב-`npx @electron/asar` לפתיחת/אריזת `app.asar`)
- הרשאות מנהל — רק אם האפליקציה מותקנת תחת `Program Files` (למשל VS Code system-install). Claude Desktop יושב ב-`%LOCALAPPDATA%` ולא דורש מנהל.

### שחזור
```powershell
.\patch.ps1 -Restore                # שחזור הכל
.\patch.ps1 -Restore -AppId claude  # שחזור אפליקציה אחת
```
או דרך התפריט: `R`.

### חשוב לדעת
כל עדכון של האפליקציה **דורס** את הפאטצ' (העדכון מחליף את `app.asar`). פשוט מריצים את הכלי שוב אחרי עדכון.

---

## English

### What it does
Most desktop apps built on Electron don't handle Hebrew/Arabic correctly — text comes out reversed or misaligned. This tool injects a tiny CSS+JS layer that fixes it using the **Unicode bidi algorithm**: every paragraph gets its direction from its first strong character. Hebrew/Arabic flow RTL; English and code stay LTR. It never rewrites the DOM, so React-based apps don't break.

### Why it's safe
- **Backs up before every change** to `%ProgramData%\ElectronRtlPatch\backups\`, with full restore.
- **Idempotent** — re-running won't double-inject (marker check).
- **Only two network destinations**: GitHub (to download) and each app's own origin. No telemetry.
- **Open source, ASCII-only JS core** — easy to read and audit.

### Install
Recommended (clone, read, run):
```powershell
git clone https://github.com/naor1237-tech/electron-rtl-patcher.git
cd electron-rtl-patcher
powershell -ExecutionPolicy Bypass -File .\patch.ps1
```
One-liner (only after reviewing the source):
```powershell
irm https://raw.githubusercontent.com/naor1237-tech/electron-rtl-patcher/main/install.ps1 | iex
```

### Requirements
- Windows 10/11
- **Node.js** in PATH (uses `npx @electron/asar`)
- Admin only for apps under `Program Files`

### Usage
```powershell
.\patch.ps1                 # interactive menu
.\patch.ps1 -Auto           # patch every detected app, no prompts
.\patch.ps1 -AppId vscode   # patch a single app
.\patch.ps1 -Restore        # restore everything
```
Fully restart the app after patching.

---

## Supported apps

| id        | App              | Type | Tested |
|-----------|------------------|------|--------|
| `claude`  | Claude Desktop   | asar | yes    |
| `vscode`  | Visual Studio Code | dir | no (experimental) |
| `cursor`  | Cursor           | dir  | no (experimental) |
| `chatgpt` | ChatGPT Desktop  | asar | no (experimental) |
| `slack`   | Slack            | asar | no (experimental) |
| `discord` | Discord          | asar | no — risky, see notes |

`asar` apps ship a packed `resources\app.asar` (the patcher extracts → injects → repacks via `@electron/asar`). `dir` apps ship an unpacked `resources\app\` folder (injected in place).

## Add your own app

Append an entry to `apps.json`:
```json
{
  "id": "myapp",
  "name": "My App",
  "type": "asar",
  "bases": ["%LOCALAPPDATA%\\MyApp"],
  "target": "resources\\app.asar",
  "htmlMatch": "*.html",
  "tested": false,
  "notes": "..."
}
```
- `bases` — folders to search (env vars expanded). Per-version `app-<ver>\` subfolders are handled automatically.
- `target` — relative path to the `.asar` (type `asar`) or the app dir (type `dir`).
- `htmlMatch` — which HTML files inside to inject into (e.g. `workbench*.html` for VS Code-based apps).

## How it works
1. Locate the app's `app.asar` / app dir from the catalog.
2. Back up the original.
3. (asar) extract with `@electron/asar` → (both) inject `<script id="electron-rtl-patch">…</script>` before `</head>` of the renderer HTML → (asar) repack.
4. Validate the repacked archive, then atomically replace the original.

The injected script: adds `unicode-bidi: plaintext; text-align: start` to text containers, forces `pre`/`code` to LTR, and stamps `dir="auto"` on RTL-bearing blocks via a throttled `MutationObserver`.

## Trust model (please read)
There is **no code signing** here. The one-line `irm | iex` install means trusting GitHub + the repo owner. The safe path is always: **clone, read `patch.ps1`, then run it**. Patching modifies vendor application files; while fully reversible via backups, you do so at your own risk. This tool is provided as-is under the MIT License.

## License
MIT © 2026 Naor Hilel — הלל פתרונות. See [LICENSE](LICENSE).
