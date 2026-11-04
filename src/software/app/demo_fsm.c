#include "demo_fsm.h"
#define FAULTS ((1u<<3)|(1u<<5)|(1u<<6)|(1u<<9)|(1u<<10)|(1u<<11)|(1u<<14)|(1u<<15))
static void fail(demo_state *d,uint32_t e){d->error=e;d->state=FAIL_LATCH;d->control&=~(SYSTEM|CAPTURE);}
void demo_begin(demo_state *d,uint64_t now){
 d->state=WAIT_POWER;d->control=READY|ARM;d->error=0;d->last_publication=0;d->init_requests=0;d->source_abort_baseline=0;d->phase_time=now;d->progress_time=now;
}
void demo_step(demo_state *d,const observation *o,uint64_t now){
 if(d->state==FAIL_LATCH)return;
 if((o->status>>24)!=11u){fail(d,0xe101);return;}
 if(o->status&FAULTS){fail(d,0xe102);return;}
 if(!(o->status&(1u<<7)) || !(o->status&(1u<<8))){
  if(d->state==WAIT_POWER && now-d->phase_time<=1000u)return;
  fail(d,0xe103);return;
 }
 switch(d->state){
 case WAIT_POWER:
  if(o->status&1u){d->control|=VIDEO|START;d->init_requests++;d->state=WAIT_INIT;d->phase_time=now;}
  else if(now-d->phase_time>1000u)fail(d,0xe110);
  break;
 case WAIT_INIT:
  if(o->status&4u){
   if(o->id_transactions!=((277u<<16)|0x5640u)){fail(d,0xe121);break;}
   d->control|=CAPTURE|SOURCE|SYSTEM;d->state=RUN_VIDEO;d->phase_time=now;d->progress_time=now;d->last_publication=o->published;
   // The always-on front end may have rejected partial data during sensor
   // initialization, before any DDR ownership. Freeze that baseline; ANY
   // subsequent abort is fatal. Do not clear or conceal the raw counter.
   d->source_abort_baseline=o->aborts;
  }else if(now-d->phase_time>15000u)fail(d,0xe120);
  break;
 case RUN_VIDEO:
  if((o->s2mm&0x89f0u)||(o->mm2s&0x89f0u)||o->aborts!=d->source_abort_baseline){fail(d,0xe130);break;}
  if(now-d->phase_time>2000u && (o->pclk<11500000u || o->pclk>12500000u)){fail(d,0xe131);break;}
  if(o->published!=d->last_publication){d->last_publication=o->published;d->progress_time=now;}
  if(now-d->progress_time>3000u)fail(d,0xe132);
  break;
 default:fail(d,0xe1ff);break;
 }
}
