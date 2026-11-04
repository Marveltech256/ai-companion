const path=require('node:path');
const fs=require('node:fs/promises');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js'));
const {requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js'));
const {logger}=require(path.join(cli,'logger.js'));
const {listFirebaseApps,AppPlatform,getAppConfig,getAppConfigFile,listAppAndroidSha,createAppAndroidSha}=require(path.join(cli,'management/apps.js'));
const {getAuthDomains,updateAuthDomains}=require(path.join(cli,'gcp/auth.js'));
logger.level='error';for(const transport of logger.transports??[])transport.level='error';
(async()=>{
 const project='ai-personal-companion';const account=getGlobalDefaultAccount();
 const options={project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})};
 await requireAuth(options);
 const api=new Client({urlPrefix:'https://identitytoolkit.googleapis.com',auth:true});
 const results=[];
 if(process.argv.includes('--require-sign-in')){
  await api.patch(`/admin/v2/projects/${project}/config`,{signIn:{anonymous:{enabled:false}}},
   {queryParams:{updateMask:'signIn.anonymous.enabled'},headers:{'x-goog-user-project':project},skipLog:{reqBody:true,resBody:true}});
 }
 for(const endpoint of ['config','defaultSupportedIdpConfigs']){
  try{
   const response=await api.get(`/admin/v2/projects/${project}/${endpoint}`,{headers:{'x-goog-user-project':project}});
   const data=response.body;
   results.push(endpoint==='config'?{endpoint,status:response.status,name:data.name,
    signIn:{email:{enabled:data.signIn?.email?.enabled===true,passwordRequired:data.signIn?.email?.passwordRequired===true},anonymous:{enabled:data.signIn?.anonymous?.enabled===true}},authorizedDomains:data.authorizedDomains}:
    {endpoint,status:response.status,providers:(data.defaultSupportedIdpConfigs??[]).map(p=>({name:p.name,enabled:p.enabled,clientId:p.clientId}))});
  }catch(e){results.push({endpoint,status:e.status??e.context?.response?.statusCode??null,error:e.message});}
 }
 try{const apps=await listFirebaseApps(project,AppPlatform.ANY);results.push({endpoint:'registered-apps',status:200,apps:apps.map(app=>({appId:app.appId,platform:app.platform,displayName:app.displayName}))});}
 catch(e){results.push({endpoint:'registered-apps',status:null,error:e.message});}
 if(process.argv.includes('--sync-public-config')){
  const apps=await listFirebaseApps(project,AppPlatform.ANY);const web=apps.filter(app=>app.platform==='WEB');
  if(web.length!==1)throw new Error('Select the intended Firebase Web app before syncing.');
  const sdk=await getAppConfig(web[0].appId,AppPlatform.WEB);
  if(sdk.projectId!==project)throw new Error('Firebase Web configuration project mismatch.');
  const configPath=path.join(process.cwd(),'config/development.json');const config=JSON.parse(await fs.readFile(configPath,'utf8'));
  config.FIREBASE_WEB_APP_ID=sdk.appId;config.FIREBASE_WEB_API_KEY=sdk.apiKey;config.FIREBASE_AUTH_DOMAIN=sdk.authDomain;
  await fs.writeFile(configPath,JSON.stringify(config,null,4)+'\n');
  const domains=await getAuthDomains(project);const combined=[...new Set([...domains,'localhost','127.0.0.1'])];
  if(combined.length!==domains.length)await updateAuthDomains(project,combined);
  const android=apps.find(app=>app.appId===config.FIREBASE_ANDROID_APP_ID);
  if(!android)throw new Error('Configured Android registration was not found.');
  const certificates=await listAppAndroidSha(project,android.appId);const normalize=value=>value.replaceAll(':','').toUpperCase();
  const wanted=[{certType:'SHA_1',shaHash:'0E:89:64:9F:EC:10:18:E4:FC:22:88:64:C5:46:86:4C:56:A3:8F:7E'},
   {certType:'SHA_256',shaHash:'72:0F:FF:A0:13:A1:A3:01:A2:F3:98:97:52:09:8D:C4:5D:83:7B:34:A4:6C:DD:D6:2C:73:56:E1:70:C4:90:EF'}];
  let added=0;for(const certificate of wanted){if(!certificates.some(c=>normalize(c.shaHash)===normalize(certificate.shaHash))){await createAppAndroidSha(project,android.appId,certificate);added++;}}
  results.push({endpoint:'public-development-setup',status:200,webAppId:sdk.appId,authorizedLocalDomains:['localhost','127.0.0.1'],debugSigningFingerprintsRegistered:wanted.length,newFingerprintsAdded:added});
 }
 if(process.argv.includes('--sync-google-config')){
  const provider=results.find(r=>r.endpoint==='defaultSupportedIdpConfigs')?.providers?.find(p=>p.name.endsWith('/google.com'));
  if(!provider?.enabled||!provider.clientId?.endsWith('.apps.googleusercontent.com'))throw new Error('Google provider is not ready.');
  const configPath=path.join(process.cwd(),'config/development.json');const config=JSON.parse(await fs.readFile(configPath,'utf8'));
  const androidPath=path.join(process.cwd(),'android/app/google-services.json');
  const iosPath=path.join(process.cwd(),'ios/Runner/GoogleService-Info.plist');
  const infoPath=path.join(process.cwd(),'ios/Runner/Info.plist');
  const androidFile=getAppConfigFile(await getAppConfig(config.FIREBASE_ANDROID_APP_ID,AppPlatform.ANDROID),AppPlatform.ANDROID);
  const iosFile=getAppConfigFile(await getAppConfig(config.FIREBASE_IOS_APP_ID,AppPlatform.IOS),AppPlatform.IOS);
  const android=JSON.parse(androidFile.fileContents);
  const client=android.client.find(c=>c.client_info.mobilesdk_app_id===config.FIREBASE_ANDROID_APP_ID);
  const plistValue=key=>iosFile.fileContents.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`))?.[1];
  const iosClientId=plistValue('CLIENT_ID');const reversed=plistValue('REVERSED_CLIENT_ID');
  if(android.project_info.project_id!==project||client?.client_info.android_client_info.package_name!=='com.aipersonalcompanion'||
   !client.oauth_client?.some(c=>c.client_type===3&&c.client_id===provider.clientId)||
   plistValue('PROJECT_ID')!==project||plistValue('GOOGLE_APP_ID')!==config.FIREBASE_IOS_APP_ID||
   plistValue('BUNDLE_ID')!==config.FIREBASE_IOS_BUNDLE_ID||!iosClientId?.endsWith('.apps.googleusercontent.com')||
   reversed!==iosClientId.split('.').reverse().join('.'))throw new Error('Native Google registration does not match the configured apps.');
  let info=await fs.readFile(infoPath,'utf8');
  const marker=/    <!-- BEGIN managed Google sign-in -->[\s\S]*?    <!-- END managed Google sign-in -->\r?\n/;
  info=info.replace(marker,'');
  if(/<key>(CFBundleURLTypes|GIDClientID|GIDServerClientID)<\/key>/.test(info))throw new Error('Review existing iOS Google configuration before replacing it.');
  const google=`    <!-- BEGIN managed Google sign-in -->\n    <key>GIDClientID</key>\n    <string>${iosClientId}</string>\n    <key>GIDServerClientID</key>\n    <string>${provider.clientId}</string>\n    <key>CFBundleURLTypes</key>\n    <array>\n        <dict>\n            <key>CFBundleTypeRole</key>\n            <string>Editor</string>\n            <key>CFBundleURLSchemes</key>\n            <array>\n                <string>${reversed}</string>\n            </array>\n        </dict>\n    </array>\n    <!-- END managed Google sign-in -->\n`;
  info=info.replace(/<dict>\r?\n/,match=>match+google);
  config.GOOGLE_SERVER_CLIENT_ID=provider.clientId;config.GOOGLE_IOS_CLIENT_ID=iosClientId;config.GOOGLE_IOS_CONFIGURED=true;
  config.FIREBASE_ANDROID_API_KEY=client.api_key[0].current_key;config.FIREBASE_IOS_API_KEY=plistValue('API_KEY');
  const backup=path.join(process.cwd(),'.cache/firebase-before-google');await fs.mkdir(backup,{recursive:true});
  for(const [source,name] of [[androidPath,'google-services.json'],[iosPath,'GoogleService-Info.plist'],[infoPath,'Info.plist'],[configPath,'development.json']]){
   try{await fs.copyFile(source,path.join(backup,name),require('node:fs').constants.COPYFILE_EXCL);}catch(error){if(error.code!=='EEXIST')throw error;}
  }
  await fs.writeFile(androidPath,androidFile.fileContents);await fs.writeFile(iosPath,iosFile.fileContents);
  await fs.writeFile(infoPath,info);await fs.writeFile(configPath,JSON.stringify(config,null,4)+'\n');
  results.push({endpoint:'google-native-configuration',status:200,androidWebAudienceMatchesProvider:true,iosClientAndCallbackMatch:true,publicDartConfigurationUpdated:true});
 }
 await fs.mkdir(path.join(process.cwd(),'.cache'),{recursive:true});
 await fs.writeFile(path.join(process.cwd(),'.cache/firebase-admin-check.json'),JSON.stringify({project,results},null,2));
 console.log(JSON.stringify({project,results},null,2));
})().catch(()=>{console.error('Firebase admin configuration could not be checked.');process.exitCode=1;});
