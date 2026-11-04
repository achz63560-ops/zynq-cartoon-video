#include <assert.h>
#include <stdio.h>
#include "demo_fsm.h"
static observation ok(void){observation o={0};o.status=0x0b000180;o.id_transactions=(277u<<16)|0x5640;o.pclk=12000000;return o;}
static demo_state running(void){demo_state d;observation o=ok();demo_begin(&d,0);o.status|=1;demo_step(&d,&o,48);assert(d.init_requests==1);o.status|=4;demo_step(&d,&o,1500);assert(d.state==RUN_VIDEO);return d;}
int main(void){
 demo_state d=running();observation o=ok();o.status|=5;
 for(unsigned n=1;n<100;n++){o.published=n;demo_step(&d,&o,1500+n*200);assert(d.state==RUN_VIDEO&&d.init_requests==1);}
 d=running();o.status|=8;demo_step(&d,&o,1501);assert(d.state==FAIL_LATCH);unsigned old=d.control;
 o=ok();for(int n=0;n<100;n++)demo_step(&d,&o,2000+n);assert(d.state==FAIL_LATCH&&d.control==old&&d.init_requests==1);
 d=running();o.s2mm=0x10;demo_step(&d,&o,1600);assert(d.error==0xe130 && !(d.control&(SYSTEM|CAPTURE)));
 d=running();o=ok();o.pclk=24000000;demo_step(&d,&o,3600);assert(d.error==0xe131);
 d=running();o=ok();demo_step(&d,&o,4600);assert(d.error==0xe132);
 demo_begin(&d,0);o=ok();demo_step(&d,&o,1001);assert(d.error==0xe110&&d.init_requests==0);
 demo_begin(&d,0);o=ok();o.status|=1;demo_step(&d,&o,50);demo_step(&d,&o,15051);assert(d.error==0xe120&&d.init_requests==1);
 demo_begin(&d,0);o=ok();o.status|=1;demo_step(&d,&o,50);o.status|=4;o.id_transactions=(277u<<16)|0xffff;demo_step(&d,&o,100);assert(d.error==0xe121);
 d=running();o=ok();o.aborts=1;demo_step(&d,&o,1600);assert(d.error==0xe130);
 d=running();o=ok();o.status^=1u<<24;demo_step(&d,&o,1600);assert(d.error==0xe101);
 demo_begin(&d,0);o=ok();o.aborts=3;o.status|=1;demo_step(&d,&o,50);o.status|=4;demo_step(&d,&o,1500);
 assert(d.state==RUN_VIDEO&&d.source_abort_baseline==3);o.published=1;demo_step(&d,&o,1600);assert(d.state==RUN_VIDEO);
 o.aborts=4;demo_step(&d,&o,1700);assert(d.error==0xe130);
 demo_begin(&d,0);o=ok();o.status&=~(1u<<8);demo_step(&d,&o,1);assert(d.state==WAIT_POWER);
 demo_step(&d,&o,1001);assert(d.error==0xe103);
 puts("TEST_PASS 12 native C FSM scenarios; no hardware or mocked sensor success claim");return 0;
}
