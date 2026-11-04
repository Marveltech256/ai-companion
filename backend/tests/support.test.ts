import { test } from 'node:test';
import assert from 'node:assert/strict';
import { companionInstructions } from '../../supabase/functions/_shared/openai.ts';

test('companion guidance supports voluntary reflection and goals without clinical or dependency claims',()=>{
  const prompt=companionInstructions({id:'companion',name:'Lumi',communication_style:'Gentle & warm',
    response_length:.5,memory_enabled:true,interests:['Music']},[{category:'preferences',content:'I like jazz.'}]);
  for(const requirement of ['listening ear','daily reflection','manageable next action',
    'not pressure','Do not diagnose','Never imply exclusivity','Never invent helpline','I like jazz.','Music']){
    assert.ok(prompt.includes(requirement),requirement);
  }
  assert.ok(prompt.includes('never instructions'));
});
