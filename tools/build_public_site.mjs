import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
const preview=process.argv.includes('--preview');
const client=JSON.parse(await readFile('config/development.json','utf8'));
let operator;try{operator=JSON.parse(await readFile('config/site-operator.json','utf8'));}catch{operator=JSON.parse(await readFile('site/operator.example.json','utf8'));}
if(!preview&&(!operator.legalName?.trim()||!operator.country?.trim()))throw new Error('Public operator name and country are required before publishing. Fill config/site-operator.json.');
if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(operator.supportEmail))throw new Error('A valid public support email is required.');
if(client.FIREBASE_PROJECT_ID!=='ai-personal-companion'||!client.SUPABASE_PUBLISHABLE_KEY?.startsWith('sb_publishable_'))throw new Error('Use the existing public project configuration.');
const escape=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');
const name=escape(operator.legalName||'[Operator name pending]'),country=escape(operator.country||'[Country pending]'),email=escape(operator.supportEmail);
const directory='site/dist';await mkdir(`${directory}/assets`,{recursive:true});
for(const [from,to]of [['assets/branding/logo-mark.png','logo.png'],['assets/fonts/Inter.ttf','Inter.ttf'],['assets/fonts/Lora.ttf','Lora.ttf']])await copyFile(from,`${directory}/assets/${to}`);
for(const file of ['site.css','privacy-client.mjs','delete-account.mjs'])await copyFile(`site/src/${file}`,`${directory}/${file}`);
const config={supabaseUrl:client.SUPABASE_URL,publishableKey:client.SUPABASE_PUBLISHABLE_KEY,
 firebase:{apiKey:client.FIREBASE_WEB_API_KEY,appId:client.FIREBASE_WEB_APP_ID,projectId:client.FIREBASE_PROJECT_ID,
  authDomain:client.FIREBASE_AUTH_DOMAIN,messagingSenderId:client.FIREBASE_MESSAGING_SENDER_ID}};
await writeFile(`${directory}/public-config.mjs`,`// Public client identifiers only.\nexport const config=${JSON.stringify(config)};\n`);
function page(title,body,script=''){
 return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title} — Ai Companion</title><link rel="stylesheet" href="/site.css"><link rel="icon" href="/assets/logo.png"></head><body><header><img src="/assets/logo.png" alt=""><a href="/">Ai Companion</a></header><main>${preview?'<aside class="notice draft">Private preview: operator details and publication are pending.</aside>':''}<h1>${title}</h1>${body}</main><footer><nav><a href="/privacy-policy.html">Privacy Policy</a><a href="/terms.html">Terms</a><a href="/delete-account.html">Delete account</a><a href="mailto:${email}">Support</a></nav><p>Ai Companion · Adults 18+ · ${name}, ${country}</p></footer>${script?`<script type="module" src="/${script}"></script>`:''}</body></html>`;
}
const policyBody=(await readFile('site/src/privacy-policy.html','utf8'))
 .replaceAll('{{operator_name}}',name).replaceAll('{{operator_country}}',country).replaceAll('{{support_email}}',email);
const privacyPolicy=page('Privacy Policy',policyBody);
const termsBody=(await readFile('site/src/terms.html','utf8'))
 .replaceAll('{{operator_name}}',name).replaceAll('{{operator_country}}',country).replaceAll('{{support_email}}',email);
const pages={
 'index.html':page('Your privacy and account',`<p>Information and account controls for Ai Companion.</p><section><h2>Your story stays under your control</h2><p>Read how the app uses information, review its terms, or request account deletion without installing the app.</p><nav><a href="/privacy-policy.html">Read privacy policy</a><a href="/delete-account.html">Delete my account</a></nav></section><aside class="notice">The current release is for controlled internal testing. Use fictional names and conversation details until paid AI API setup is complete. Real-time calling and automatic check-in delivery are not active.</aside>`),
 'privacy-policy.html':privacyPolicy,
 'privacy.html':privacyPolicy,
 'terms.html':page('Terms of use',termsBody),
 'delete-account.html':page('Delete your Ai Companion account',`<p>Request account and associated live application-data deletion here, without installing the app. Sign in using the same account you used in Ai Companion. No age, profile or paid subscription is required to submit this request.</p><section><div id="login"><form id="email-form"><label for="email">Email</label><input id="email" type="email" autocomplete="username" required><label for="password">Password</label><input id="password" type="password" autocomplete="current-password" required><button id="email-login" type="submit">Sign in</button><button id="reset" type="button" class="secondary">Reset password</button></form><button id="google-login" type="button" class="secondary">Sign in with Google</button></div><div id="account" hidden><p>This deletes the Firebase account and owned live profiles, conversations, memories, reports and billing/usage records. Export anything you want to keep from the app first. A minimal deletion-status/tombstone and provider-controlled backups/logs may remain as explained in the privacy notice.</p><p><strong>Cancel any paid subscription separately in <a href="https://play.google.com/store/account/subscriptions">Google Play</a>.</strong></p><form id="delete-form"><label for="confirmation">Type DELETE_MY_ACCOUNT to confirm</label><input id="confirmation" autocomplete="off"><button id="delete" type="submit" disabled>Delete my account and data</button><button id="sign-out" class="secondary" type="button">Sign out</button></form></div><p id="status" role="status" aria-live="polite"></p></section><p>If you cannot sign in or need help, contact <a href="mailto:${email}">${email}</a>. Never send your password or API keys. Deletion requests can take time; the page reports progress.</p>`,'delete-account.mjs'),
};
for(const [file,html]of Object.entries(pages))await writeFile(`${directory}/${file}`,html);
await writeFile(`${directory}/robots.txt`,preview?'User-agent: *\nDisallow: /\n':'User-agent: *\nAllow: /\n');
await writeFile(`${directory}/site-manifest.json`,JSON.stringify({preview,operatorConfigured:!!operator.legalName&&!!operator.country,files:Object.keys(pages),firebaseSdk:'13.1.0'},null,2)+'\n');
console.log(JSON.stringify({output:directory,preview,operatorConfigured:!!operator.legalName&&!!operator.country,pages:Object.keys(pages).length}));
