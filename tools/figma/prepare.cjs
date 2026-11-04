// Convert the ORIGINAL local export into a compact Flutter scene description.
// Positions, paints, geometry, text, and baselines are copied, never approximated.
const fs = require('node:fs');
const path = require('node:path');
const doc = JSON.parse(fs.readFileSync('design/source/document.json', 'utf8'));
const id = g => `${g.sessionID}:${g.localID}`;
const children = new Map();
for (const node of doc.nodeChanges) {
  if (!node.parentIndex) continue;
  const parent = id(node.parentIndex.guid);
  if (!children.has(parent)) children.set(parent, []);
  children.get(parent).push(node);
}
for (const list of children.values()) list.sort((a,b) =>
  a.parentIndex.position < b.parentIndex.position ? -1 : 1);
const geometry = {};
function commands(index) {
  if (geometry[index]) return;
  const bytes = Buffer.from(Object.values(doc.blobs[index].bytes));
  const result = [];
  for (let offset=0; offset<bytes.length;) {
    const op = bytes[offset++];
    if (op===0) continue;
    const count = ({1:2,2:2,3:4,4:6,5:0})[op];
    if (count===undefined || offset+count*4>bytes.length)
      throw new Error(`Unsupported original geometry ${index} at ${offset-1}`);
    const command=[op];
    for(let i=0;i<count;i++,offset+=4) command.push(bytes.readFloatLE(offset));
    result.push(command);
  }
  geometry[index]=result;
}
function paint(p) {
  return Object.fromEntries(['type','color','opacity','visible','blendMode','stops','transform']
    .filter(k=>p[k]!==undefined).map(k=>[k,p[k]]));
}
function scene(n) {
  for (const g of [...(n.fillGeometry||[]),...(n.strokeGeometry||[])]) commands(g.commandsBlob);
  return {
    id:id(n.guid), name:n.name, type:n.type, size:n.size,
    transform:n.transform, visible:n.visible, opacity:n.opacity,
    fills:(n.fillPaints||[]).map(paint), strokes:(n.strokePaints||[]).map(paint),
    fillGeometry:n.fillGeometry||[], strokeGeometry:n.strokeGeometry||[],
    effects:n.effects||[], clip:n.type==='FRAME' && n.frameMaskDisabled===false,
    radius:n.cornerRadius||0,
    ...(n.textData ? {text:n.textData.characters,font:n.fontName,
      fontSize:n.fontSize,letterSpacing:n.letterSpacing,
      align:n.textAlignHorizontal,lines:n.derivedTextData?.baselines||[],
      weight:n.derivedTextData?.fontMetaData?.[0]?.fontWeight||400} : {}),
    children:(children.get(id(n.guid))||[]).map(scene)
  };
}
fs.mkdirSync('assets/design',{recursive:true});
const names=['setup','home','conversation','voice','memories','desktop_conversation','desktop_memories'];
const frameIds=[6619,6688,6754,6816,6870,6939,7076];
const frames=frameIds.map(localID=>doc.nodeChanges.find(n=>n.guid.sessionID===2 && n.guid.localID===localID));
for(let i=0;i<frames.length;i++) {
  fs.writeFileSync(`assets/design/${names[i]}.json`,JSON.stringify(scene(frames[i])));
}
fs.writeFileSync('assets/design/geometry.json',JSON.stringify(geometry));
const fontSummary=[...new Set(doc.nodeChanges.filter(n=>n.fontName)
  .map(n=>`${n.fontName.family} / ${n.fontName.style}`))];
const manifest={fileKey:'ZR1ovxn0yC9WzkPjQYI7ZL',sourceOriginFileKey:doc.originFileKey,sourceSha256:
  require('node:crypto').createHash('sha256').update(fs.readFileSync('design/source/morrow.fig')).digest('hex'),
  frames:frames.map((n,i)=>({id:id(n.guid),name:n.name,asset:`${names[i]}.json`,size:n.size})),
  fonts:fontSummary,geometryCount:Object.keys(geometry).length};
fs.writeFileSync('design/manifest.json',JSON.stringify(manifest,null,2));
console.log(JSON.stringify(manifest,null,2));
