/**
 * E-LIBRARY BACKEND  (Google Apps Script, bound to the Google Sheet used as database)
 *
 * Deploy: Deploy > New deployment > Web app > Execute as: Me > Who has access: Anyone
 * First run: select function `setup` and press Run (authorise the permissions).
 */

const SCHEMA = {
  Users:       ['id', 'role', 'name', 'email', 'salt', 'hash', 'createdAt'],
  Programs:    ['id', 'name', 'semesters', 'createdAt'],
  Semesters:   ['id', 'programId', 'number', 'name'],
  Units:       ['id', 'semesterId', 'name', 'code'],
  Topics:      ['id', 'unitId', 'title', 'videoUrl', 'fileId', 'fileName', 'ext', 'size', 'origSize', 'createdAt'],
  Allocations: ['id', 'tutorId', 'unitId'],
  Vouchers:    ['id', 'code', 'active', 'createdAt'],
  Students:    ['id', 'name', 'voucher', 'firstSeen', 'lastSeen', 'logins'],
  TutorDone:   ['id', 'topicId', 'tutorId', 'doneAt'],
  Comments:    ['id', 'topicId', 'userId', 'name', 'role', 'text', 'ts'],
  Materials:   ['id', 'topicId', 'tutorId', 'type', 'title', 'content', 'ts']
};
const SESSION_SECONDS = 21600; // 6 hours (CacheService maximum)

/* ------------------------------------------------------------------ setup */
function setup() {
  const ss = SpreadsheetApp.getActive();
  Object.keys(SCHEMA).forEach(function (n) {
    let s = ss.getSheetByName(n);
    if (!s) s = ss.insertSheet(n);
    if (s.getLastRow() === 0) { s.appendRow(SCHEMA[n]); s.setFrozenRows(1); }
  });
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('FOLDER_ID')) {
    props.setProperty('FOLDER_ID', DriveApp.createFolder('ELibraryFiles').getId());
  }
  if (!rows('Users').some(function (u) { return u.role === 'admin'; })) {
    const email = props.getProperty('ADMIN_EMAIL') || Session.getEffectiveUser().getEmail();
    const pw = props.getProperty('ADMIN_PASSWORD') || 'Admin@12345';
    createUser('admin', 'Administrator', email, pw);
  }
  if (!rows('Vouchers').length) newVoucher({}, {});
  const def = ss.getSheetByName('Sheet1');
  if (def && ss.getSheets().length > 1 && def.getLastRow() === 0) ss.deleteSheet(def);
  Logger.log('Setup complete. Admin login = ' + (props.getProperty('ADMIN_EMAIL') || Session.getEffectiveUser().getEmail()) +
    ' / ' + (props.getProperty('ADMIN_PASSWORD') || 'Admin@12345') + ' (change it after first login)');
}

/* ------------------------------------------------------------ HTTP entry */
function doGet(e) {
  const p = (e && e.parameter) || {};
  if (!p.action) {
    return HtmlService.createHtmlOutputFromFile('index')
      .setTitle('E-Library Admin')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }
  let out;
  try {
    out = { ok: true, data: dispatch(p.action, JSON.parse(p.payload || '{}')) };
  } catch (err) {
    out = { ok: false, error: err.message, code: err.code || '' };
  }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

/** Called by the admin dashboard through google.script.run */
function api(action, payload) {
  try {
    return JSON.parse(JSON.stringify({ ok: true, data: dispatch(action, payload || {}) }));
  } catch (err) {
    return { ok: false, error: err.message, code: err.code || '' };
  }
}

function fail(msg, code) { const e = new Error(msg); e.code = code || ''; throw e; }

/* -------------------------------------------------------------- dispatch */
const WRITES = ['studentLogin', 'addProgram', 'deleteProgram', 'addUnit', 'updateUnit', 'deleteUnit', 'addTopic',
  'updateTopic', 'deleteTopic', 'addTutor', 'deleteTutor', 'resetTutorPassword', 'allocate', 'unallocate',
  'newVoucher', 'setVoucher', 'tutorMark', 'addMaterial', 'addComment', 'changePassword', 'confirmReset'];

function dispatch(action, p) {
  const open = { studentLogin: studentLogin, login: login, requestReset: requestReset, confirmReset: confirmReset };
  const ANY = { tree: getTree, getFile: getFile, tutorDone: tutorDone, comments: comments, addComment: addComment,
    materials: materials, changePassword: changePassword };
  const TUTOR = { tutorUnits: tutorUnits, tutorMark: tutorMark, addMaterial: addMaterial };
  const ADMIN = { stats: stats, adminStudents: adminStudents, addProgram: addProgram, deleteProgram: deleteProgram,
    addUnit: addUnit, updateUnit: updateUnit, deleteUnit: deleteUnit, addTopic: addTopic, updateTopic: updateTopic,
    deleteTopic: deleteTopic, listTutors: listTutors, addTutor: addTutor, deleteTutor: deleteTutor,
    resetTutorPassword: resetTutorPassword, allocate: allocate, unallocate: unallocate,
    listAllocations: listAllocations, listVouchers: listVouchers, newVoucher: newVoucher, setVoucher: setVoucher };

  let fn, s = {};
  if (open[action]) fn = open[action];
  else {
    s = auth(p.token);
    if (ANY[action]) fn = ANY[action];
    else if (TUTOR[action]) { if (s.role !== 'tutor') fail('Tutors only', 'FORBIDDEN'); fn = TUTOR[action]; }
    else if (ADMIN[action]) { if (s.role !== 'admin') fail('Admin only', 'FORBIDDEN'); fn = ADMIN[action]; }
    else fail('Unknown action: ' + action);
  }
  if (WRITES.indexOf(action) >= 0) {
    const lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try { return fn(p, s); } finally { lock.releaseLock(); }
  }
  return fn(p, s);
}

/* -------------------------------------------------------- sheet helpers */
function sheet(name) { return SpreadsheetApp.getActive().getSheetByName(name); }
function rows(name) {
  const v = sheet(name).getDataRange().getValues();
  const h = v.shift();
  return v.map(function (r) { const o = {}; h.forEach(function (k, i) { o[k] = r[i]; }); return o; });
}
function add(name, obj) {
  obj.id = obj.id || Utilities.getUuid();
  sheet(name).appendRow(SCHEMA[name].map(function (k) { return obj[k] === undefined ? '' : obj[k]; }));
  return obj;
}
function update(name, id, patch) {
  const s = sheet(name), v = s.getDataRange().getValues(), h = v[0], ix = h.indexOf('id');
  for (let i = 1; i < v.length; i++) {
    if (String(v[i][ix]) === String(id)) {
      Object.keys(patch).forEach(function (k) { const c = h.indexOf(k); if (c >= 0) s.getRange(i + 1, c + 1).setValue(patch[k]); });
      return true;
    }
  }
  return false;
}
function removeWhere(name, fn) {
  const s = sheet(name), v = s.getDataRange().getValues(), h = v[0];
  for (let i = v.length - 1; i >= 1; i--) {
    const o = {}; h.forEach(function (k, j) { o[k] = v[i][j]; });
    if (fn(o)) s.deleteRow(i + 1);
  }
}
function bust() { CacheService.getScriptCache().removeAll(['tree', 'vch', 'tdone']); }

/* ------------------------------------------------------ users / sessions */
function hash(salt, pw) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, salt + pw)
    .map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); }).join('');
}
function createUser(role, name, email, pw) {
  const salt = Utilities.getUuid();
  return add('Users', { role: role, name: name, email: String(email).toLowerCase().trim(), salt: salt, hash: hash(salt, pw), createdAt: Date.now() });
}
function newSession(obj) {
  const t = Utilities.getUuid() + Utilities.getUuid();
  CacheService.getScriptCache().put('t_' + t, JSON.stringify(obj), SESSION_SECONDS);
  return t;
}
function activeCodes() {
  const c = CacheService.getScriptCache(), r = c.get('vch');
  if (r) return JSON.parse(r);
  const l = rows('Vouchers').filter(function (v) { return v.active === true; }).map(function (v) { return v.code; });
  c.put('vch', JSON.stringify(l), 60);
  return l;
}
function auth(token) {
  const raw = token ? CacheService.getScriptCache().get('t_' + token) : null;
  if (!raw) fail('Session expired, please sign in again', 'AUTH');
  const s = JSON.parse(raw);
  if (s.role === 'student' && activeCodes().indexOf(s.voucher) < 0) fail('This voucher has been deactivated. Enter a new code.', 'VOUCHER');
  return s;
}

function studentLogin(p) {
  const code = String(p.voucher || '').trim().toUpperCase();
  if (!p.deviceId) fail('Missing device id');
  if (activeCodes().indexOf(code) < 0) fail('Invalid or deactivated voucher code', 'VOUCHER');
  const now = Date.now();
  const existing = rows('Students').filter(function (r) { return r.id === p.deviceId; })[0];
  if (existing) {
    update('Students', p.deviceId, { name: p.name || existing.name, voucher: code, lastSeen: now, logins: Number(existing.logins || 0) + 1 });
  } else {
    add('Students', { id: p.deviceId, name: p.name || '', voucher: code, firstSeen: now, lastSeen: now, logins: 1 });
  }
  const token = newSession({ role: 'student', uid: p.deviceId, voucher: code, name: p.name || '' });
  return { token: token };
}

function login(p) {
  const email = String(p.email || '').toLowerCase().trim();
  const u = rows('Users').filter(function (r) { return r.email === email && r.role === p.role; })[0];
  if (!u || hash(u.salt, String(p.password || '')) !== u.hash) fail('Wrong email or password');
  const token = newSession({ role: u.role, uid: u.id, name: u.name, email: u.email });
  return { token: token, user: { id: u.id, name: u.name, role: u.role, email: u.email } };
}

function changePassword(p, s) {
  if (s.role === 'student') fail('Not allowed');
  const u = rows('Users').filter(function (r) { return r.id === s.uid; })[0];
  if (!u || hash(u.salt, String(p.oldPassword || '')) !== u.hash) fail('Current password is wrong');
  if (String(p.newPassword || '').length < 6) fail('New password must be at least 6 characters');
  const salt = Utilities.getUuid();
  update('Users', u.id, { salt: salt, hash: hash(salt, p.newPassword) });
  return true;
}

function requestReset(p) {
  const email = String(p.email || '').toLowerCase().trim();
  const u = rows('Users').filter(function (r) { return r.email === email && r.role !== 'student'; })[0];
  if (u) {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    CacheService.getScriptCache().put('r_' + email, code, 600);
    MailApp.sendEmail(email, 'E-Library password reset code',
      'Hello ' + u.name + ',\n\nYour verification code is: ' + code + '\nIt expires in 10 minutes.\n\nIf you did not request this, ignore this email.');
  }
  return true; // never reveal whether the email exists
}
function confirmReset(p) {
  const email = String(p.email || '').toLowerCase().trim();
  const code = CacheService.getScriptCache().get('r_' + email);
  if (!code || String(p.code).trim() !== code) fail('Invalid or expired code');
  if (String(p.newPassword || '').length < 6) fail('Password must be at least 6 characters');
  const u = rows('Users').filter(function (r) { return r.email === email && r.role !== 'student'; })[0];
  if (!u) fail('Account not found');
  const salt = Utilities.getUuid();
  update('Users', u.id, { salt: salt, hash: hash(salt, p.newPassword) });
  CacheService.getScriptCache().remove('r_' + email);
  return true;
}

/* ------------------------------------------------------------ read APIs */
function getTree() {
  const c = CacheService.getScriptCache(), hit = c.get('tree');
  if (hit) return JSON.parse(hit);
  const P = rows('Programs'), S = rows('Semesters'), U = rows('Units'), T = rows('Topics');
  const tree = {
    programs: P.map(function (p) {
      return {
        id: p.id, name: p.name,
        semesters: S.filter(function (s) { return s.programId === p.id; })
          .sort(function (a, b) { return a.number - b.number; })
          .map(function (s) {
            return {
              id: s.id, number: s.number, name: s.name,
              units: U.filter(function (u) { return u.semesterId === s.id; }).map(function (u) {
                return {
                  id: u.id, name: u.name, code: u.code,
                  topics: T.filter(function (t) { return t.unitId === u.id; })
                    .sort(function (a, b) { return a.createdAt - b.createdAt; })
                    .map(function (t) {
                      return { id: t.id, title: t.title, videoUrl: t.videoUrl, fileName: t.fileName, ext: t.ext, size: t.size, hasFile: !!t.fileId };
                    })
                };
              })
            };
          })
      };
    })
  };
  try { c.put('tree', JSON.stringify(tree), 300); } catch (e) { /* too large to cache */ }
  return tree;
}

function getFile(p) {
  const t = rows('Topics').filter(function (r) { return r.id === p.topicId; })[0];
  if (!t || !t.fileId) fail('No file for this topic');
  const bytes = DriveApp.getFileById(t.fileId).getBlob().getBytes();
  return { name: t.fileName, ext: t.ext, gz: true, b64: Utilities.base64Encode(bytes) };
}

function tutorDone() {
  const c = CacheService.getScriptCache(), hit = c.get('tdone');
  if (hit) return JSON.parse(hit);
  const l = rows('TutorDone').map(function (r) { return r.topicId; });
  c.put('tdone', JSON.stringify(l), 60);
  return l;
}

function comments(p, s) {
  return rows('Comments').filter(function (r) { return r.topicId === p.topicId; })
    .sort(function (a, b) { return a.ts - b.ts; }).slice(-200)
    .map(function (r) { return { id: r.id, name: r.name, role: r.role, text: r.text, ts: r.ts, mine: r.userId === s.uid }; });
}
function addComment(p, s) {
  const text = String(p.text || '').trim().slice(0, 1000);
  if (!text) fail('Empty message');
  const name = s.role === 'student' ? (p.name || s.name || 'Student') : s.name;
  add('Comments', { topicId: p.topicId, userId: s.uid, name: name, role: s.role, text: text, ts: Date.now() });
  return true;
}
function materials(p) {
  return rows('Materials').filter(function (r) { return r.topicId === p.topicId; })
    .sort(function (a, b) { return b.ts - a.ts; });
}

/* ----------------------------------------------------------- tutor APIs */
function tutorUnits(p, s) {
  const alloc = rows('Allocations').filter(function (a) { return a.tutorId === s.uid; });
  const tree = getTree(), out = [];
  tree.programs.forEach(function (pr) {
    pr.semesters.forEach(function (sem) {
      sem.units.forEach(function (u) {
        if (alloc.some(function (a) { return a.unitId === u.id; })) {
          out.push({ unit: { id: u.id, name: u.name, code: u.code, semester: sem.name, program: pr.name }, topics: u.topics });
        }
      });
    });
  });
  return out;
}
function tutorAllocatedToTopic(s, topicId) {
  const t = rows('Topics').filter(function (r) { return r.id === topicId; })[0];
  if (!t) fail('Topic not found');
  const ok = rows('Allocations').some(function (a) { return a.tutorId === s.uid && a.unitId === t.unitId; });
  if (!ok) fail('You are not allocated to this course unit', 'FORBIDDEN');
}
function tutorMark(p, s) {
  tutorAllocatedToTopic(s, p.topicId);
  // all tutors on the same unit share one timeline: record is keyed by topic only
  removeWhere('TutorDone', function (r) { return r.topicId === p.topicId; });
  if (p.done) add('TutorDone', { topicId: p.topicId, tutorId: s.uid, doneAt: Date.now() });
  CacheService.getScriptCache().remove('tdone');
  return true;
}
function addMaterial(p, s) {
  tutorAllocatedToTopic(s, p.topicId);
  add('Materials', { topicId: p.topicId, tutorId: s.uid, type: p.type || 'note', title: p.title || '', content: p.content || '', ts: Date.now() });
  return true;
}

/* ----------------------------------------------------------- admin APIs */
function stats() {
  return {
    programs: rows('Programs').length, units: rows('Units').length, topics: rows('Topics').length,
    tutors: rows('Users').filter(function (u) { return u.role === 'tutor'; }).length,
    students: rows('Students').length, vouchers: rows('Vouchers').filter(function (v) { return v.active === true; }).length
  };
}
function adminStudents() { return rows('Students').sort(function (a, b) { return b.lastSeen - a.lastSeen; }); }

function addProgram(p) {
  const n = Math.max(1, Math.min(20, parseInt(p.semesters, 10) || 2));
  if (!p.name) fail('Program name required');
  const pr = add('Programs', { name: p.name, semesters: n, createdAt: Date.now() });
  for (let i = 1; i <= n; i++) {
    add('Semesters', { programId: pr.id, number: i, name: 'Year ' + Math.ceil(i / 2) + ' · Semester ' + (i % 2 === 1 ? 1 : 2) });
  }
  bust(); return pr;
}
function deleteProgram(p) {
  const sems = rows('Semesters').filter(function (s) { return s.programId === p.id; }).map(function (s) { return s.id; });
  sems.forEach(function (sid) { deleteSemesterContent(sid); });
  removeWhere('Semesters', function (s) { return s.programId === p.id; });
  removeWhere('Programs', function (r) { return r.id === p.id; });
  bust(); return true;
}
function deleteSemesterContent(semId) {
  rows('Units').filter(function (u) { return u.semesterId === semId; }).forEach(function (u) { deleteUnitContent(u.id); });
  removeWhere('Units', function (u) { return u.semesterId === semId; });
}
function deleteUnitContent(unitId) {
  rows('Topics').filter(function (t) { return t.unitId === unitId; }).forEach(function (t) { trashFile(t.fileId); });
  removeWhere('Topics', function (t) { return t.unitId === unitId; });
  removeWhere('Allocations', function (a) { return a.unitId === unitId; });
}
function addUnit(p) {
  if (!p.name) fail('Course unit name required');
  const u = add('Units', { semesterId: p.semesterId, name: p.name, code: p.code || '' });
  bust(); return u;
}
function updateUnit(p) { update('Units', p.id, { name: p.name, code: p.code || '' }); bust(); return true; }
function deleteUnit(p) {
  deleteUnitContent(p.id);
  removeWhere('Units', function (u) { return u.id === p.id; });
  bust(); return true;
}
function trashFile(id) { if (id) { try { DriveApp.getFileById(id).setTrashed(true); } catch (e) { } } }

function addTopic(p) {
  if (!p.title) fail('Topic title required');
  let fileId = '', size = 0, ext = '';
  if (p.b64) {
    const bytes = Utilities.base64Decode(p.b64);
    const blob = Utilities.newBlob(bytes, 'application/gzip', p.fileName + '.gz');
    fileId = DriveApp.getFolderById(PropertiesService.getScriptProperties().getProperty('FOLDER_ID')).createFile(blob).getId();
    size = bytes.length;
    ext = String(p.fileName).split('.').pop().toLowerCase();
  }
  const t = add('Topics', { unitId: p.unitId, title: p.title, videoUrl: p.videoUrl || '', fileId: fileId, fileName: p.fileName || '',
    ext: ext, size: size, origSize: p.origSize || 0, createdAt: Date.now() });
  bust(); return t;
}
function updateTopic(p) { update('Topics', p.id, { title: p.title, videoUrl: p.videoUrl || '' }); bust(); return true; }
function deleteTopic(p) {
  const t = rows('Topics').filter(function (r) { return r.id === p.id; })[0];
  if (t) trashFile(t.fileId);
  removeWhere('Topics', function (r) { return r.id === p.id; });
  removeWhere('TutorDone', function (r) { return r.topicId === p.id; });
  removeWhere('Comments', function (r) { return r.topicId === p.id; });
  removeWhere('Materials', function (r) { return r.topicId === p.id; });
  bust(); return true;
}

function listTutors() {
  return rows('Users').filter(function (u) { return u.role === 'tutor'; })
    .map(function (u) { return { id: u.id, name: u.name, email: u.email }; });
}
function addTutor(p) {
  const email = String(p.email || '').toLowerCase().trim();
  if (!p.name || !email || String(p.password || '').length < 6) fail('Name, email and a password (6+ chars) are required');
  if (rows('Users').some(function (u) { return u.email === email; })) fail('That email is already registered');
  const u = createUser('tutor', p.name, email, p.password);
  return { id: u.id };
}
function deleteTutor(p) {
  removeWhere('Users', function (u) { return u.id === p.id && u.role === 'tutor'; });
  removeWhere('Allocations', function (a) { return a.tutorId === p.id; });
  return true;
}
function resetTutorPassword(p) {
  if (String(p.password || '').length < 6) fail('Password must be at least 6 characters');
  const salt = Utilities.getUuid();
  update('Users', p.id, { salt: salt, hash: hash(salt, p.password) });
  return true;
}
function allocate(p) {
  if (rows('Allocations').some(function (a) { return a.tutorId === p.tutorId && a.unitId === p.unitId; })) return true;
  add('Allocations', { tutorId: p.tutorId, unitId: p.unitId });
  return true;
}
function unallocate(p) { removeWhere('Allocations', function (a) { return a.id === p.id; }); return true; }
function listAllocations() { return rows('Allocations'); }

function listVouchers() { return rows('Vouchers').sort(function (a, b) { return b.createdAt - a.createdAt; }); }
function newVoucher(p, s) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = 'ELIB-';
  for (let i = 0; i < 6; i++) code += chars.charAt(Math.floor(Math.random() * chars.length));
  const v = add('Vouchers', { code: code, active: true, createdAt: Date.now() });
  bust(); return v;
}
function setVoucher(p) { update('Vouchers', p.id, { active: !!p.active }); bust(); return true; }
