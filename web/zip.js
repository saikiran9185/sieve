// A ZIP writer, stored (uncompressed).
//
// "Everything in one folder" has to be one file in a browser, because a page cannot write a
// directory unless the person picks one — and the folder mirror already covers that case.
// PDFs are already compressed, so storing rather than deflating costs almost nothing and
// removes any need for a compression library.

const enc = new TextEncoder();

function crcTable() {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
}
const TABLE = crcTable();

/// DOS time and date, which is what the format stores. Wrong by up to two seconds by design.
function dosStamp(d = new Date()) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return { time, date };
}

export class Zip {
  constructor() { this.entries = []; }

  /// Content is kept as a Blob and never held in memory as bytes. A library can easily be a
  /// gigabyte of PDFs, and reading each one into an array to checksum it — then keeping it
  /// there until the archive is assembled — is what makes a tab run out of memory and die.
  /// The checksum is taken a few megabytes at a time, and the final archive is assembled
  /// from the Blobs themselves, which the browser keeps on disk.
  async add(name, content) {
    const blob = content instanceof Blob ? content
      : new Blob([content instanceof Uint8Array ? content : enc.encode(String(content))]);
    this.entries.push({
      name: enc.encode(name), blob, size: blob.size,
      crc: await crc32Blob(blob), ...dosStamp(),
    });
  }

  finish() {
    const parts = [];
    const central = [];
    let offset = 0;

    for (const e of this.entries) {
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);            // version needed
      local.setUint16(6, 0x0800, true);        // UTF-8 names
      local.setUint16(8, 0, true);             // stored
      local.setUint16(10, e.time, true);
      local.setUint16(12, e.date, true);
      local.setUint32(14, e.crc, true);
      local.setUint32(18, e.size, true);
      local.setUint32(22, e.size, true);
      local.setUint16(26, e.name.length, true);
      local.setUint16(28, 0, true);
      parts.push(new Uint8Array(local.buffer), e.name, e.blob);

      const dir = new DataView(new ArrayBuffer(46));
      dir.setUint32(0, 0x02014b50, true);
      dir.setUint16(4, 20, true);
      dir.setUint16(6, 20, true);
      dir.setUint16(8, 0x0800, true);
      dir.setUint16(10, 0, true);
      dir.setUint16(12, e.time, true);
      dir.setUint16(14, e.date, true);
      dir.setUint32(16, e.crc, true);
      dir.setUint32(20, e.size, true);
      dir.setUint32(24, e.size, true);
      dir.setUint16(28, e.name.length, true);
      dir.setUint32(42, offset, true);
      central.push(new Uint8Array(dir.buffer), e.name);
      offset += 30 + e.name.length + e.size;
    }

    const centralSize = central.reduce((n, p) => n + p.length, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, this.entries.length, true);
    end.setUint16(10, this.entries.length, true);
    end.setUint32(12, centralSize, true);
    end.setUint32(16, offset, true);
    return new Blob([...parts, ...central, new Uint8Array(end.buffer)], { type: 'application/zip' });
  }
}

/// Checksums a Blob a chunk at a time, so a 200MB PDF costs 4MB of memory rather than 200.
async function crc32Blob(blob, chunkSize = 4 * 1024 * 1024) {
  let c = 0xFFFFFFFF;
  for (let at = 0; at < blob.size; at += chunkSize) {
    const bytes = new Uint8Array(await blob.slice(at, at + chunkSize).arrayBuffer());
    for (let i = 0; i < bytes.length; i++) c = TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}

/// Safe inside a zip and on every filesystem that will unpack it.
export function safeName(s, fallback = 'file') {
  const base = String(s || '').replace(/[\/\\:*?"<>|\x00-\x1f]/g, ' ').replace(/\s+/g, ' ').trim();
  return (base || fallback).slice(0, 90);
}

// ---------------------------------------------------------------- reading one back

/// Reads an archive Sieve wrote. Only stored (uncompressed) entries, which is all this
/// writer produces, and it works off Blob slices so a gigabyte of PDFs is never held in
/// memory at once.
export async function readZip(blob) {
  const tail = new DataView(await blob.slice(Math.max(0, blob.size - 66000)).arrayBuffer());
  const base = Math.max(0, blob.size - 66000);
  let end = -1;
  for (let i = tail.byteLength - 22; i >= 0; i--) {
    if (tail.getUint32(i, true) === 0x06054b50) { end = i; break; }
  }
  if (end < 0) throw new Error('That file is not a Sieve archive.');
  const count = tail.getUint16(end + 10, true);
  const dirSize = tail.getUint32(end + 12, true);
  const dirAt = tail.getUint32(end + 16, true);

  const dir = new DataView(await blob.slice(dirAt, dirAt + dirSize).arrayBuffer());
  const names = new TextDecoder();
  const out = [];
  let at = 0;
  for (let i = 0; i < count && at + 46 <= dir.byteLength; i++) {
    if (dir.getUint32(at, true) !== 0x02014b50) break;
    const method = dir.getUint16(at + 10, true);
    const size = dir.getUint32(at + 24, true);
    const nameLen = dir.getUint16(at + 28, true);
    const extraLen = dir.getUint16(at + 30, true);
    const commentLen = dir.getUint16(at + 32, true);
    const localAt = dir.getUint32(at + 42, true);
    const name = names.decode(new Uint8Array(dir.buffer, at + 46, nameLen));
    at += 46 + nameLen + extraLen + commentLen;
    if (method !== 0) continue;                 // stored only; this writer makes no others

    // The local header repeats the name and extra field, and its lengths are the ones that
    // count — some writers pad the extra field differently in the two places.
    const head = new DataView(await blob.slice(localAt, localAt + 30).arrayBuffer());
    const from = localAt + 30 + head.getUint16(26, true) + head.getUint16(28, true);
    out.push({ name, blob: blob.slice(from, from + size) });
  }
  if (!out.length) throw new Error('That archive has nothing Sieve can read.');
  return out;
}
