import { runtime } from '../_shared/runtime.ts';
import { createVoiceApi } from '../_shared/voice.ts';
import {createAudioProvider} from '../_shared/audio_factory.ts';
import {billingAccessDatabase} from '../_shared/billing_access.ts';
const audio=createAudioProvider(name=>Deno.env.get(name));
const deps=runtime(name=>Deno.env.get(name));
Deno.serve(createVoiceApi({...deps,db:billingAccessDatabase(deps,name=>Deno.env.get(name)),audio}));
