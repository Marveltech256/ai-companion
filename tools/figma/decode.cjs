// Read a user-authorized, original Figma local export. Never connects to Figma.
// Format references: github.com/evanw/kiwi and
// github.com/sunyui/figma-parser/blob/main/scripts/decode_kiwi.cjs
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const kiwi = require('kiwi-schema');

const input = path.resolve(process.argv[2] || 'design/source/canvas.fig');
const output = path.resolve(process.argv[3] || 'design/source/document.json');
const source = fs.readFileSync(input);
if (source.toString('ascii', 0, 8) !== 'fig-kiwi') {
  throw new Error('Expected an original fig-kiwi canvas export.');
}
const chunks = [];
for (let offset = 12; offset < source.length;) {
  if (offset + 4 > source.length) throw new Error('Truncated chunk header.');
  const length = source.readUInt32LE(offset);
  offset += 4;
  if (offset + length > source.length) throw new Error('Truncated chunk.');
  chunks.push(source.subarray(offset, offset + length));
  offset += length;
}
if (chunks.length < 2) throw new Error('Schema or document chunk missing.');
const schema = kiwi.decodeBinarySchema(zlib.inflateRawSync(chunks[0]));
const codec = kiwi.compileSchema(schema);
const compressed = chunks[1];
const payload = compressed.readUInt32LE(0) === 0xfd2fb528
  ? zlib.zstdDecompressSync(compressed)
  : zlib.inflateRawSync(compressed);
const document = codec.decodeMessage(payload);
fs.writeFileSync(output, JSON.stringify(document, null, 2));
console.log(JSON.stringify({ version: source.readUInt32LE(8),
  nodes: document.nodeChanges?.length, output, keys: Object.keys(document) }));
