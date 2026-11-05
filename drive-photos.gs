/**
 * Party photos feed for the birthday invite.
 *
 * Lists the photos in one Google Drive folder so the invite's "Party photos" gallery can show them.
 * It returns only each photo's Drive ID and date added: no file names, no folder name, nothing else.
 *
 * Setup (once):
 *  1. Go to script.google.com → New project, delete what's there and paste this whole file.
 *  2. Put your folder's ID below. It's the last part of the folder's address:
 *     drive.google.com/drive/folders/THIS_PART
 *  3. Run "checkSetup" once (choose it in the toolbar → Run) and allow access when asked.
 *     The log shows how many photos it found and whether sharing is right.
 *  4. Deploy → New deployment → type "Web app".
 *     Execute as: Me.  Who has access: Anyone.  → Deploy, then copy the Web app URL (ends in /exec).
 *  5. Paste that URL into Party HQ → Photos → Google Drive folder, and tap "Save & test".
 *
 * The folder must be shared as "Anyone with the link → Viewer", or guests' phones can't load the photos.
 * New photos show up on the invite within about a minute (the list is cached for 60 seconds).
 */

const FOLDER_ID = 'PASTE_YOUR_FOLDER_ID_HERE';
const MAX_PHOTOS = 200;
const CACHE_SECONDS = 60;

function doGet() {
  const cache = CacheService.getScriptCache();
  let body = cache.get('photos');
  if (!body) {
    body = JSON.stringify(listPhotos_());
    cache.put('photos', body, CACHE_SECONDS);
  }
  return ContentService.createTextOutput(body).setMimeType(ContentService.MimeType.JSON);
}

function listPhotos_() {
  try {
    const files = DriveApp.getFolderById(FOLDER_ID).getFiles();
    const photos = [];
    while (files.hasNext()) {
      const f = files.next();
      if (f.isTrashed() || !/^image\//.test(f.getMimeType())) continue;
      photos.push({ id: f.getId(), name: f.getName(), added: f.getDateCreated().toISOString() });
    }
    // Phone photos are named in the order they were taken (IMG_0001, IMG_0002…), so sort by name.
    photos.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
    return {
      ok: true,
      count: photos.length,
      photos: photos.slice(0, MAX_PHOTOS).map(p => ({ id: p.id, added: p.added }))
    };
  } catch (e) {
    return { ok: false, error: 'Could not read the folder. Check FOLDER_ID and that this account can open it.' };
  }
}

/** Run this from the editor to check everything before deploying. Results appear in the execution log. */
function checkSetup() {
  if (FOLDER_ID === 'PASTE_YOUR_FOLDER_ID_HERE') { Logger.log('Put your folder ID in FOLDER_ID first.'); return; }
  const folder = DriveApp.getFolderById(FOLDER_ID);
  const shared = folder.getSharingAccess();
  Logger.log('Folder sharing: ' + shared + (shared === DriveApp.Access.ANYONE_WITH_LINK || shared === DriveApp.Access.ANYONE
    ? '  ✓ good'
    : '  ✗ set the folder to "Anyone with the link → Viewer"'));
  const result = listPhotos_();
  Logger.log(result.ok ? 'Photos found: ' + result.count : result.error);
  CacheService.getScriptCache().remove('photos');
}
