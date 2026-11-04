#ifndef DEMO_FSM_H
#define DEMO_FSM_H
#include <stdint.h>
enum {READY=1u,ARM=2u,VIDEO=4u,START=8u,CAPTURE=16u,SYSTEM=32u,SOURCE=64u};
enum {WAIT_POWER=1,WAIT_INIT=2,RUN_VIDEO=3,FAIL_LATCH=4};
typedef struct {uint32_t status,id_transactions,published,displayed,pclk,algorithm,source_sof,source_eof,aborts,s2mm,mm2s;} observation;
typedef struct {uint32_t state,control,error,last_publication,init_requests,source_abort_baseline;uint64_t phase_time,progress_time;} demo_state;
void demo_begin(demo_state *d,uint64_t now);
void demo_step(demo_state *d,const observation *o,uint64_t now);
#endif
