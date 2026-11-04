// Creates a local upload-key candidate; never registers it with Google Play.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
if(!process.argv.includes('--first-upload')&&!process.argv.includes('--new-local-candidate'))throw Error('Specify --first-upload or --new-local-candidate. An existing Play app needs its registered upload key.');
if(process.platform!=='win32')throw Error('This helper uses Windows per-user ACLs. Configure signing manually on another OS.');
const root=process.cwd(),android=path.join(root,'android'),folder=path.join(android,'keystores');
if(!fs.readFileSync(path.join(android,'app/build.gradle.kts'),'utf8').includes('com.aipersonalcompanion'))throw Error('Run from the Ai Companion workspace.');
const properties=path.join(android,'key.properties'),keystore=path.join(folder,'ai-companion-upload.jks');
if(fs.existsSync(properties)||fs.existsSync(keystore))throw Error('Existing signing files found. They will not be replaced.');
const javaHome=process.env.JAVA_HOME||path.join(process.env.ProgramFiles||'C:/Program Files','Android','Android Studio','jbr');
const keytool=path.join(javaHome,'bin','keytool.exe');
if(!fs.existsSync(keytool))throw Error('Set JAVA_HOME to the installed JDK.');
function command(binary,args,env=process.env){
 const result=spawnSync(binary,args,{encoding:'utf8',windowsHide:true,env});
 if(result.error||result.status!==0)throw Error(`Signing helper command failed: ${path.basename(binary)}. Existing files were preserved; no secret output is printed.`);
 return result.stdout;
}
const sid=command('whoami.exe',['/user','/fo','csv','/nh']).match(/S-\d(?:-\d+)+/)?.[0];
if(!sid)throw Error('Unable to determine the current Windows user SID.');
fs.mkdirSync(folder,{recursive:true});
command('icacls.exe',[folder,'/inheritance:r','/grant:r',`*${sid}:(OI)(CI)F`,'*S-1-5-18:(OI)(CI)F']);
// Restrict the empty file before writing its random password.
fs.closeSync(fs.openSync(properties,'wx'));
command('icacls.exe',[properties,'/inheritance:r','/grant:r',`*${sid}:F`,'*S-1-5-18:F']);
const password=crypto.randomBytes(32).toString('base64url');
fs.writeFileSync(properties,`# PRIVATE: back up this file and the upload keystore together.\nstoreFile=keystores/ai-companion-upload.jks\nstorePassword=${password}\nkeyPassword=${password}\nkeyAlias=upload\n`);
const env={...process.env,AIC_UPLOAD_STORE_PASSWORD:password};
command(keytool,['-genkeypair','-keystore',keystore,'-storetype','JKS','-keyalg','RSA','-keysize','4096',
 '-validity','10000','-alias','upload','-dname','CN=Ai Companion Upload, OU=Mobile, O=Ai Companion',
 '-storepass:env','AIC_UPLOAD_STORE_PASSWORD','-keypass:env','AIC_UPLOAD_STORE_PASSWORD'],env);
const certificate=path.join(root,'releases','0.1.0+1','upload-certificate.pem');
command(keytool,['-exportcert','-rfc','-keystore',keystore,'-alias','upload','-storepass:env','AIC_UPLOAD_STORE_PASSWORD','-file',certificate],env);
const cert=new crypto.X509Certificate(fs.readFileSync(certificate));
const report={created_at_utc:new Date().toISOString(),keystore:'android/keystores/ai-companion-upload.jks',
 first_upload_confirmed:process.argv.includes('--first-upload'),registered_with_play:false,
 private_properties:'android/key.properties',public_certificate:'releases/0.1.0+1/upload-certificate.pem',
 sha1:cert.fingerprint,sha256:cert.fingerprint256,valid_from:cert.validFrom,valid_to:cert.validTo,
 key_algorithm:cert.publicKey.asymmetricKeyType,private_password_logged:false};
fs.mkdirSync(path.join(root,'.cache'),{recursive:true});
fs.writeFileSync(path.join(root,'.cache/android-release-signing.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
