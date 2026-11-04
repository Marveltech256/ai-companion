// Offline validation of the signed artifact; signing passwords are not read.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process'),{inflateRawSync}=require('node:zlib');
const bundle=path.resolve(process.argv[2]||'releases/0.1.0+1/ai-companion-0.1.0-1-internal.aab');
const root=process.cwd(),versionCode=process.argv[3]||'1',versionName=process.argv[4]||'0.1.0';
const reviewFile='config/PLAY_REVIEW_ACCESS.private.txt';
const reviewCode=fs.existsSync(reviewFile)?fs.readFileSync(reviewFile,'utf8').match(/^Access code: ([A-Za-z0-9_-]{43})$/m)?.[1]:undefined;
const java=process.env.JAVA_HOME||'C:/Program Files/Android/Android Studio/jbr';
const tool=JSON.parse(fs.readFileSync('.cache/release-tools/bundletool.json','utf8').replace(/^\uFEFF/,''));
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(tool.file)).digest('hex'),tool.sha256);
function run(binary,args){const r=spawnSync(path.join(java,'bin',binary+'.exe'),args,{encoding:'utf8',windowsHide:true,maxBuffer:16777216});
 if(r.error||r.status!==0)throw Error(`${binary} validation failed: ${(r.stdout+r.stderr).slice(-2000)}`);return r.stdout;}
const bt=(...args)=>run('java',['-jar',tool.file,...args]);
bt('validate',`--bundle=${bundle}`);
assert.match(run('jarsigner',['-verify',bundle]),/jar verified/i);
const certificateText=run('keytool',['-printcert','-jarfile',bundle,'-rfc']);
const actual=new crypto.X509Certificate(certificateText.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/)[0]);
const expected=new crypto.X509Certificate(fs.readFileSync('releases/0.1.0+1/upload-certificate.pem'));
const signing=JSON.parse(fs.readFileSync('.cache/android-release-signing.json','utf8').replace(/^\uFEFF/,''));
assert.ok(actual.raw.equals(expected.raw),'Bundle must match the exported upload certificate.');
const xml=bt('dump','manifest',`--bundle=${bundle}`,'--module=base');
const attr=(element,name)=>xml.match(new RegExp(`<${element}\\b[^>]*?\\s${name}="([^"]*)"`))?.[1];
assert.equal(attr('manifest','package'),'com.aipersonalcompanion');
assert.equal(attr('manifest','android:versionCode'),versionCode);
assert.equal(attr('manifest','android:versionName'),versionName);
assert.equal(attr('application','android:debuggable')??'false','false');
assert.ok(Number(attr('uses-sdk','android:targetSdkVersion'))>=36);
const config=JSON.parse(bt('dump','config',`--bundle=${bundle}`));
assert.ok(JSON.stringify(config).includes('PAGE_ALIGNMENT_16K'),'Native packaging must request 16 KB alignment.');
// Read central-directory metadata and only inflate native libraries, in memory.
const bytes=fs.readFileSync(bundle),end=bytes.lastIndexOf(Buffer.from([0x50,0x4b,0x05,0x06]));
assert.ok(end>=0);const count=bytes.readUInt16LE(end+10);assert.notEqual(count,65535,'ZIP64 is not supported by this verifier.');
let cursor=bytes.readUInt32LE(end+16);const native=[];
for(let index=0;index<count;index++){
 assert.equal(bytes.readUInt32LE(cursor),0x02014b50);
 const method=bytes.readUInt16LE(cursor+10),size=bytes.readUInt32LE(cursor+20),plainSize=bytes.readUInt32LE(cursor+24),
  nameSize=bytes.readUInt16LE(cursor+28),extraSize=bytes.readUInt16LE(cursor+30),commentSize=bytes.readUInt16LE(cursor+32),local=bytes.readUInt32LE(cursor+42);
 const name=bytes.toString('utf8',cursor+46,cursor+46+nameSize),lower=name.toLowerCase();
 cursor+=46+nameSize+extraSize+commentSize;
 assert.ok(!/\.(jks|keystore)$|\/(key\.properties|\.env)$|service-account|adminsdk|\.private\.|play_review_access/.test(lower),'Private file packaged in bundle.');
 if(!name.startsWith('base/lib/')||!name.endsWith('.so'))continue;
 assert.equal(bytes.readUInt32LE(local),0x04034b50);
 const start=local+30+bytes.readUInt16LE(local+26)+bytes.readUInt16LE(local+28),compressed=bytes.subarray(start,start+size);
 const elf=method===0?compressed:method===8?inflateRawSync(compressed):null;assert.ok(elf);assert.equal(elf.length,plainSize);
 if(reviewCode)assert.ok(!elf.includes(Buffer.from(reviewCode)),'Private review code embedded in a native library.');
 assert.equal(elf.toString('hex',0,4),'7f454c46');const is64=elf[4]===2,little=elf[5]===1;
 const u16=o=>little?elf.readUInt16LE(o):elf.readUInt16BE(o),u32=o=>little?elf.readUInt32LE(o):elf.readUInt32BE(o),
  u64=o=>Number(little?elf.readBigUInt64LE(o):elf.readBigUInt64BE(o));
 const phoff=is64?u64(32):u32(28),entrySize=u16(is64?54:42),entries=u16(is64?56:44),alignments=[];
 for(let n=0;n<entries;n++){const o=phoff+n*entrySize;if(u32(o)!==1)continue;
  const position=is64?u64(o+8):u32(o+4),address=is64?u64(o+16):u32(o+8),alignment=is64?u64(o+48):u32(o+28);
  alignments.push(alignment);if(is64)assert.ok(alignment>=16384&&(address-position)%16384===0,`16 KB ELF alignment failed: ${name}`);}
 native.push({file:name,is_64_bit:is64,load_segment_alignment_bytes:alignments});
}
assert.ok(native.some(n=>n.file.includes('/arm64-v8a/')));
const report={checked_at_utc:new Date().toISOString(),bundle:path.basename(bundle),version_name:versionName,version_code:Number(versionCode),
 application_id:attr('manifest','package'),minimum_sdk:Number(attr('uses-sdk','android:minSdkVersion')),target_sdk:Number(attr('uses-sdk','android:targetSdkVersion')),
 debuggable:false,bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),bundletool_version:tool.version,
 bundletool_validation:'passed',jar_signature:'verified',upload_certificate_matches:true,upload_certificate_sha256:actual.fingerprint256,
 native_packaging_16kb:true,native_libraries:native,private_signing_files_packaged:false,private_review_code_checked:!!reviewCode,private_review_code_embedded:false,play_console_uploaded:false,
 first_play_upload_confirmed:signing.first_upload_confirmed,
 existing_play_upload_key_compatibility:signing.first_upload_confirmed?'not_applicable_first_upload':'not_checked',device_runtime_verified:false};
fs.writeFileSync(path.join(path.dirname(bundle),'artifact-verification.json'),JSON.stringify(report,null,2)+'\n');
const {native_libraries,...summary}=report;console.log(JSON.stringify({...summary,native_library_count:native_libraries.length},null,2));
