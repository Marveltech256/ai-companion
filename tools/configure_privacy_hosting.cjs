// Adds only the dedicated privacy site and its exact auth/API origins.
// No billing, provider credentials, existing hosting release or user data changes.
const path=require('node:path'),fs=require('node:fs'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js')),{requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js')),{logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const t of logger.transports??[])t.level='error';
const project='ai-personal-companion',site='ai-personal-companion-privacy',ref='rvokidwyzwygpzzkpqck';
const hosts=[`${site}.web.app`,`${site}.firebaseapp.com`];
const original='http://localhost:52100,http://127.0.0.1:52100,https://ai-personal-companion.firebaseapp.com,https://ai-personal-companion.web.app';
const expanded=[original,...hosts.map(h=>`https://${h}`)].join(',');
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
const binary=process.env.AI_COMPANION_SUPABASE_CLI;let stage='preflight';
const run=args=>execFileSync(binary,args,{encoding:'utf8',stdio:['ignore','pipe','pipe'],windowsHide:true,timeout:60000});
(async()=>{
 if(!binary||!path.isAbsolute(binary))throw Error('Supply the owning Supabase CLI path.');
 const operator=JSON.parse(fs.readFileSync('config/site-operator.json','utf8'));
 if(operator.legalName!=='Marvel tech solutions'||operator.country!=='Uganda')throw Error('Operator details do not match the supplied identity.');
 const manifest=JSON.parse(fs.readFileSync('site/dist/site-manifest.json','utf8'));
 if(manifest.preview||!manifest.operatorConfigured)throw Error('Build the production pages before hosting setup.');
 const account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const hosting=new Client({urlPrefix:'https://firebasehosting.googleapis.com',apiVersion:'v1beta1',auth:true});
 const auth=new Client({urlPrefix:'https://identitytoolkit.googleapis.com',apiVersion:'admin/v2',auth:true});
 const metadata=JSON.parse(run(['secrets','list',`--remote=${ref}`,'--output','json']));
 const origins=metadata.find(s=>s.name==='ALLOWED_ORIGINS'),billing=metadata.find(s=>s.name==='BILLING_FEATURE_ENABLED');
 const originHash=origins?.digest??origins?.value;
 if(![digest(original),digest(expanded)].includes(originHash))throw Error('Browser allowlist changed; preserve and review it before extending.');
 if((billing?.digest??billing?.value)!==digest('false'))throw Error('Purchases must remain disabled.');
 const sites=(await hosting.get(`/projects/${project}/sites`)).body.sites??[];
 if(!sites.some(s=>s.name===`projects/${project}/sites/${site}`)){
  stage='validate-site';await hosting.post(`/projects/${project}/sites`,{appId:''},{queryParams:{siteId:site,validateOnly:'true'}});
  stage='create-privacy-site';await hosting.post(`/projects/${project}/sites`,{appId:''},{queryParams:{siteId:site}});
 }
 stage='extend-auth-domains';
 const current=(await auth.get(`/projects/${project}/config`)).body.authorizedDomains??[];
 const desired=[...new Set([...current,...hosts])];
 if(desired.length!==current.length)await auth.patch(`/projects/${project}/config`,{authorizedDomains:desired},{queryParams:{update_mask:'authorizedDomains'}});
 stage='extend-api-origins';
 // The allowlist is public URLs; its verified digest prevents clobbering unknown additions.
 if(originHash!==digest(expanded))run(['secrets','set',`ALLOWED_ORIGINS=${expanded}`,`--remote=${ref}`,'--yes']);
 const updated=JSON.parse(run(['secrets','list',`--remote=${ref}`,'--output','json'])).find(s=>s.name==='ALLOWED_ORIGINS');
 if((updated?.digest??updated?.value)!==digest(expanded))throw Error('Origin update could not be verified.');
 const report={checked_at_utc:new Date().toISOString(),project,site,operator:operator.legalName,country:operator.country,
  auth_domains_added:hosts,existing_domains_preserved:current.every(h=>desired.includes(h)),api_origins_added:hosts.map(h=>`https://${h}`),
  purchases_enabled:false,existing_hosting_deployed:false};
 fs.writeFileSync('.cache/privacy-hosting-configuration.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(JSON.stringify({stage,complete:false,status:error.status??null,message:'Privacy hosting setup stopped; raw credentials/responses suppressed.'}));process.exitCode=1;});
