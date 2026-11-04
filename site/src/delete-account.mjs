import {initializeApp} from 'https://www.gstatic.com/firebasejs/13.1.0/firebase-app.js';
import {getAuth,setPersistence,inMemoryPersistence,signInWithEmailAndPassword,GoogleAuthProvider,signInWithPopup,sendPasswordResetEmail,signOut}
 from 'https://www.gstatic.com/firebasejs/13.1.0/firebase-auth.js';
import {config} from './public-config.mjs';
import {privacyRequest} from './privacy-client.mjs';
const auth=getAuth(initializeApp(config.firebase));await setPersistence(auth,inMemoryPersistence);
const $=id=>document.getElementById(id),message=text=>{$('status').textContent=text;};
let signedIn=null,busy=false;
function controls(){
 $('delete').disabled=busy||!signedIn||$('confirmation').value!=='DELETE_MY_ACCOUNT';
 for(const id of ['email-login','google-login','reset','sign-out'])$(id).disabled=busy;
 $('account').hidden=!signedIn;$('login').hidden=!!signedIn;
}
async function action(work){if(busy)return;busy=true;controls();try{await work();}catch(e){message(e.message||'Please try again.');}finally{busy=false;controls();}}
$('email-form').addEventListener('submit',event=>{event.preventDefault();action(async()=>{
 try{const result=await signInWithEmailAndPassword(auth,$('email').value.trim(),$('password').value);signedIn=result.user;}
 catch{throw new Error('Could not sign in. Check your email/password or use Google sign-in.');}
 finally{$('password').value='';}
 message('Signed in. Review the deletion details before confirming.');
});});
$('google-login').addEventListener('click',()=>action(async()=>{
 try{signedIn=(await signInWithPopup(auth,new GoogleAuthProvider())).user;}
 catch{throw new Error('Google sign-in was not completed. Please try again.');}
 message('Signed in. Review the deletion details before confirming.');
}));
$('reset').addEventListener('click',()=>action(async()=>{
 const email=$('email').value.trim();if(!email)throw new Error('Enter your email address first.');
 try{await sendPasswordResetEmail(auth,email);}catch{}
 message('If this email supports password sign-in, you can use the reset instructions sent to it.');
}));
$('sign-out').addEventListener('click',()=>action(async()=>{await signOut(auth);signedIn=null;$('confirmation').value='';message('Signed out.');}));
$('confirmation').addEventListener('input',controls);
$('delete-form').addEventListener('submit',event=>{event.preventDefault();action(async()=>{
 if(!signedIn||$('confirmation').value!=='DELETE_MY_ACCOUNT')throw new Error('Sign in and type the confirmation exactly.');
 const token=await signedIn.getIdToken(true);
 await privacyRequest(config,token,'request_account_erasure',{confirmation:'DELETE_MY_ACCOUNT'});
 message('Your account deletion was requested. Checking progress…');
 for(let attempt=0;attempt<20;attempt++){
  const state=await privacyRequest(config,token,'erasure_status');
  if(state.status==='complete'){await signOut(auth);signedIn=null;$('confirmation').value='';message('Your Ai Companion account and live application data have been deleted.');return;}
  if(state.status==='failed'){message('Your request is saved but deletion needs another attempt. Please contact support if it remains pending.');return;}
  await new Promise(resolve=>setTimeout(resolve,2000));
 }
 message('Your deletion request is saved and still processing. Contact support if you need help checking it.');
});});
controls();
