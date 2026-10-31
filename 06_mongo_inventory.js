// App discovery 06: MongoDB inventory from METADATA only (no collection scans).
// Lists databases, collections, estimated sizes/counts, indexes, GridFS, keyword hits.
// SPEED: FAST (seconds to ~2 minutes). SAFETY: GREEN (metadata commands only).
// Only run if script 02 showed mongod ALREADY running. Never start mongod for this.
//
// Usage (legacy shell, works with old servers; ES5 syntax on purpose):
//   mongo --quiet --port 27017 06_mongo_inventory.js
//   mongo --quiet -u USER -p --authenticationDatabase admin 06_mongo_inventory.js     (if auth on)
// Optional PEEK: show field NAMES and TYPES (never values) of the FIRST document in each collection:
//   mongo --quiet --eval 'var PEEK=true' 06_mongo_inventory.js
//   PEEK reads one document in natural (disk) order with an empty filter: no index, no scan, ~1 disk read.
//   It is YELLOW: a single document can be up to 16 MB (big geometry arrays). Run it after the plain pass.

var G = '\x1b[32m', Y = '\x1b[33m', R = '\x1b[31m', B = '\x1b[1;34m', C = '\x1b[36m', N = '\x1b[0m';
var KW = /til|lym|tumor|cancer|heat|annot|app.annotations|object|metadata|image|slide|execution|provenance|segment|geometry|footprint|imagescope|aperio|case|subject|collection/i;
var SUSPECT = ['collections', 'app.annotations', 'app.annotationss'];
var DO_PEEK = (typeof PEEK !== 'undefined' && PEEK);

function human(b) {
  if (b === undefined || b === null) return '?';
  if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + ' TB';
  if (b >= 1073741824) return (b / 1073741824).toFixed(1) + ' GB';
  if (b >= 1048576) return (b / 1048576).toFixed(1) + ' MB';
  return (b / 1024).toFixed(0) + ' KB';
}
function pad(s, n) { s = String(s); while (s.length < n) s += ' '; return s; }

// Describe a document's shape: field -> type. Values are NOT printed (privacy), except ObjectId dates.
function shape(o, prefix, depth, out) {
  for (var k in o) {
    if (!o.hasOwnProperty(k)) continue;
    var v = o[k], name = prefix + k, t;
    if (v === null) t = 'null';
    else if (v instanceof ObjectId) t = 'ObjectId (created ' + v.getTimestamp().toISOString().slice(0, 10) + ')';
    else if (v instanceof Date) t = 'Date';
    else if (v instanceof BinData) t = 'BinData (binary, ' + v.length() + ' bytes)';
    else if (v instanceof Array) t = 'Array[' + v.length + ']' + (v.length ? ' of ' + (v[0] instanceof Array ? 'Array' : typeof v[0]) : '');
    else if (typeof v === 'object') t = 'Object';
    else if (typeof v === 'string') t = 'string (len ' + v.length + ')';
    else t = typeof v;
    out.push((KW.test(k) ? Y : '') + '      ' + pad(name, 45) + N + ' ' + t);
    if (depth < 3 && v && typeof v === 'object' && !(v instanceof Array) && !(v instanceof ObjectId) && !(v instanceof Date) && !(v instanceof BinData))
      shape(v, name + '.', depth + 1, out);
    if (depth < 3 && v instanceof Array && v.length && typeof v[0] === 'object' && !(v[0] instanceof Array))
      shape(v[0], name + '[0].', depth + 1, out);
  }
  return out;
}

print(B + '===== MongoDB inventory: ' + db.getMongo().host + '  server version ' + db.version() + ' =====' + N);
try {
  var opts = db.adminCommand({ getCmdLineOpts: 1 });
  print(C + 'Startup options (passwords not stored here): ' + N + tojson(opts.parsed).replace(/\s+/g, ' ').slice(0, 400));
} catch (e) { print(Y + 'getCmdLineOpts not allowed: ' + e + N); }

var rows = [];
var dbs = db.adminCommand({ listDatabases: 1 });
if (!dbs.ok) { print(R + 'listDatabases failed (auth needed?): ' + tojson(dbs) + N); quit(1); }

dbs.databases.forEach(function (d) {
  var name = d.name, sdb = db.getSiblingDB(name);
  print('\n' + B + '===== DATABASE ' + name + '  (on disk ' + human(d.sizeOnDisk) + ') =====' + N);
  if (name === 'local' || name === 'config') { print('   system database, skipped'); return; }
  var colls = sdb.getCollectionNames();
  SUSPECT.forEach(function (s) {
    print((colls.indexOf(s) >= 0 ? G + '   [EXISTS] ' : R + '   [absent] ') + 'collection "' + s + '"' + N);
  });
  colls.forEach(function (c) {
    if (/^system\./.test(c)) return;
    var st = {};
    try { st = sdb.getCollection(c).stats(); } catch (e) { st = { err: String(e) }; }
    var col = KW.test(c) ? Y : G;
    print(col + '  ' + pad(c, 32) + N + ' docs~' + pad(st.count, 12) + ' data ' + pad(human(st.size), 10) +
          ' disk ' + pad(human(st.storageSize), 10) + ' indexes ' + st.nindexes + ' (' + human(st.totalIndexSize) + ')' +
          (/\.(files|chunks)$/.test(c) ? R + '  <- GridFS (files stored inside Mongo)' + N : '') + (st.err ? R + ' ' + st.err + N : ''));
    try {
      sdb.getCollection(c).getIndexes().forEach(function (ix) { print(C + '      index ' + tojson(ix.key).replace(/\s+/g, ' ') + N); });
    } catch (e) {}
    rows.push([name, c, human(st.size), st.count]);
    if (DO_PEEK) {
      var doc = sdb.getCollection(c).findOne();
      if (doc) shape(doc, '', 0, []).forEach(function (l) { print(l); });
      else print('      (empty)');
    }
  });
});

print('\n' + B + '===== Worksheet rows (paste into inventory; counts are METADATA ESTIMATES) =====' + N);
print('| Server | Database | Collection | Est. Size | Est. Doc Count | Purpose | Confidence |');
rows.forEach(function (r) { print('| ' + db.getMongo().host + ' | ' + r[0] + ' | ' + r[1] + ' | ' + r[2] + ' | ~' + r[3] + ' | ? | U |'); });
print(Y + '\nYellow = name matches a keyword (til, tumor, app.annotations, app.objects, metadata, image...). Hints only, not proof.' + N);
