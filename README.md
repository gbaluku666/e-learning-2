# E-Library

One Flutter codebase (Android app, Windows desktop app, website) + a Google Apps Script backend with the admin dashboard, using Google Sheets as the database.

```
e-library/
├── backend/            -> paste into Google Apps Script (bound to a Google Sheet)
│   ├── Code.gs         API + business logic
│   ├── index.html      Admin dashboard (served by the web app)
│   └── appsscript.json manifest
├── lib/                -> Flutter app (student + tutor, all platforms)
├── pubspec.yaml
└── .github/workflows/build.yml   -> builds APK, Windows app, website
```

## 1. Backend + admin dashboard (do this first)

1. Create a new Google Sheet (name it "E-Library DB").
2. **Extensions → Apps Script.** Replace the contents of `Code.gs` with `backend/Code.gs`.
3. Add a file: **+ → HTML**, name it exactly `index`, paste `backend/index.html`.
4. Project Settings → tick "Show appsscript.json", paste `backend/appsscript.json`.
5. (Optional) Project Settings → Script properties: add `ADMIN_EMAIL` and `ADMIN_PASSWORD`. Without them the admin is your Google email with password `Admin@12345`.
6. Select the function **setup** and click Run; approve permissions. It creates all sheets, a Drive folder for files, the admin account and a first voucher.
7. **Deploy → New deployment → Web app**: Execute as *Me*, Who has access *Anyone*. Copy the Web App URL (`.../exec`).
8. Open that URL in a browser: this is the **admin dashboard**. Sign in, add a program, a tutor, upload topics, and copy a voucher for students.

Whenever you change the code, use **Deploy → Manage deployments → Edit → New version**.

## 2. Flutter apps via GitHub

1. Open `lib/config.dart` and paste your Web App URL into `kApiUrl`.
2. Create a GitHub repo and push the contents of this folder (everything except nothing — keep the structure).
3. Repo **Settings → Pages → Source: GitHub Actions** (for the website).
4. The workflow runs on every push (or Actions → *Build E-Library apps* → Run workflow). Download from the run's **Artifacts**:
   - `e-library-android-apk` → install on phones
   - `e-library-windows` → zip of the desktop app (run `e_library.exe`)
   - `e-library-web` → also auto-published to GitHub Pages

The workflow runs `flutter create` itself to generate the android/windows/web folders, so you only need the files in this project.

## Notes

- PDF viewing uses Syncfusion's community-licensed viewer. Syncfusion shows a license banner until you register a free community key (`SyncfusionLicense.registerLicense('KEY')` in `main()`).
- Files are compressed (gzip) in the admin's browser before upload and decompressed inside the app. Max 25 MB per file.
- Office preview in the app: .pdf (full), .docx and .pptx (text only), .xlsx (tables). Older .doc/.xls/.ppt are not previewable.
- The YouTube player plays inside the app on Android and the website. On the Windows app the "Watch video" button opens the browser.
- Students keep progress, downloads and timetable on their device under an auto-generated identifier; they stay signed in until the admin deactivates their voucher, and then only need a new code.
- Admin sign-in exists only on the web dashboard. The Flutter app has no admin login on phones; on web/desktop the "Admin" tab opens the dashboard.
