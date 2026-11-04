// Read-only metadata checks. Authentication and secret values are never printed.
const path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js')),{requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js')),{logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const t of logger.transports??[])t.level='error';
(async()=>{
 const project='ai-personal-companion',account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const hosting=new Client({urlPrefix:'https://firebasehosting.googleapis.com',apiVersion:'v1beta1',auth:true});
 const auth=new Client({urlPrefix:'https://identitytoolkit.googleapis.com',apiVersion:'admin/v2',auth:true});
 const sites=(await hosting.get(`/projects/${project}/sites`)).body.sites??[];
 const config=(await auth.get(`/projects/${project}/config`)).body;
 const binary=process.env.AI_COMPANION_SUPABASE_CLI;
 if(!binary||!path.isAbsolute(binary))throw Error('Supply the owning Supabase CLI path.');
 const meta=JSON.parse(execFileSync(binary,['secrets','list','--remote=rvokidwyzwygpzzkpqck','--output','json'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
 const current=meta.find(s=>s.name==='ALLOWED_ORIGINS'),billing=meta.find(s=>s.name==='BILLING_FEATURE_ENABLED');
 const known='http://localhost:52100,http://127.0.0.1:52100,https://ai-personal-companion.firebaseapp.com,https://ai-personal-companion.web.app';
 const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
 console.log(JSON.stringify({project,sites:sites.map(s=>({name:s.name,defaultUrl:s.defaultUrl})),authorizedDomains:config.authorizedDomains,
  anonymousSignInEnabled:config.signIn?.anonymous?.enabled===true,
  originsMetadataFields:current?Object.keys(current):[],originsValueLength:current?.value?.length??0,
  knownOriginsMatch:[known,known+',https://ai-personal-companion-privacy.web.app,https://ai-personal-companion-privacy.firebaseapp.com']
   .some(value=>[current?.digest,current?.value].includes(digest(value))),originsRawMatch:current?.value===known,
  billingFlagOff:[billing?.digest,billing?.value].includes(digest('false'))||billing?.value==='false'},null,2));
})().catch(error=>{console.error(JSON.stringify({preflightPassed:false,status:error.status??null,message:'Hosting preflight failed; credentials and raw responses suppressed.'}));process.exitCode=1;});
