/* FSBL performs PS/DDR/PLL/MIO initialization once. This application does NOT
 * call ps7_init, change clock/boot/DevCfg registers, or drive SCCB directly. */
#include <stdint.h>
#include "demo_fsm.h"
#define REG(a) (*(volatile uint32_t *)(a))
#define GPIO 0x41200000u
#define TIMER 0xf8f00200u
#define FB_FIRST 0x10000000u
#define FB_END 0x10600000u
volatile uint32_t app_signature=0x53444131u;
volatile uint32_t app_status,error_address,app_error,app_init_requests;
volatile observation app_observed;
volatile uint32_t window_source_eof,window_published,window_displayed,window_ms;
static uint32_t command,flags,sequence;
static demo_state state;
static inline void barrier(void){__asm__ volatile("dsb sy\nisb sy":::"memory");}
static uint32_t sctlr(void){uint32_t v;__asm__ volatile("mrc p15,0,%0,c1,c0,0":"=r"(v));return v;}
static void instruction_cache_only(void){
 uint32_t v=sctlr(),zero=0;
 __asm__ volatile("dsb sy\nmcr p15,0,%0,c7,c5,0\nisb sy"::"r"(zero):"memory");
 v|=0x1000u;
 __asm__ volatile("mcr p15,0,%0,c1,c0,0\nisb sy"::"r"(v):"memory");
}
static uint64_t ticks(void){uint32_t h,l,h2;do{h=REG(TIMER+4);l=REG(TIMER);h2=REG(TIMER+4);}while(h!=h2);return ((uint64_t)h<<32)|l;}
static uint64_t origin;
// Matched PS clock is CPU666.666MHz; A9 global timer runs CPU/2.
static uint64_t milliseconds(void){return (ticks()-origin)/333333u;}
static void halt(uint32_t code,uint32_t address){app_error=code;error_address=address;app_status=0xdead0011u;barrier();for(;;)__asm__ volatile("wfi");}
static uint32_t exchange(unsigned page){
 uint64_t end=milliseconds()+1000u;unsigned spins=0;uint32_t v;
 sequence=(sequence+1u)&15u;command=(sequence<<28)|((page&15u)<<12)|(flags&511u);
 REG(GPIO)=command;barrier();
 do {v=REG(GPIO+8);if((v>>28)==sequence)return v&0x0fffffffu;
 }while(milliseconds()<end && ++spins<1000000u);
 // Unknown AXI/control state: never send a blind cleanup/retry command.
 halt(0xe010u,command);return 0;
}
static observation observe(void){
 observation o;
 o.status=exchange(0);o.id_transactions=exchange(1);o.published=exchange(2);o.displayed=exchange(3);
 o.pclk=exchange(4);o.algorithm=exchange(5);o.source_sof=exchange(10);o.source_eof=exchange(11);
 o.aborts=exchange(12);o.s2mm=exchange(14);o.mm2s=exchange(15);return o;
}
void main(void){
 if(sctlr()&0x1005u)halt(0xe001u,sctlr());
 if(REG(0xf8f02100u)&1u)halt(0xe004u,REG(0xf8f02100u));
 // Enable the private global timer only if FSBL left it disabled. No reset.
 if(!(REG(TIMER+8)&1u))REG(TIMER+8)|=1u;
 barrier();origin=ticks();app_status=1;
 flags=0;sequence=0;exchange(0);
 for(uint32_t a=FB_FIRST;a<FB_END;a+=4u)REG(a)=a^0x5aa59669u;
 barrier();
 for(uint32_t a=FB_FIRST;a<FB_END;a+=4u)if(REG(a)!=(a^0x5aa59669u))halt(0xe002u,a);
 for(uint32_t a=FB_FIRST;a<FB_END;a+=4u)REG(a)=0;
 barrier();
 for(uint32_t a=FB_FIRST;a<FB_END;a+=4u)if(REG(a)!=0)halt(0xe003u,a);
 // Immutable application instructions can use L1 I-cache. D-cache, L2 and MMU
 // remain disabled; avoid sustained uncached DDR instruction fetch contention
 // during status polling. No frame data becomes CPU-cached.
 instruction_cache_only();
 if((sctlr()&0x1005u)!=0x1000u)halt(0xe005u,sctlr());
 // CPU never touches framebuffer data again.
 demo_begin(&state,milliseconds());flags=state.control;exchange(0);
 uint64_t last_window=milliseconds();uint32_t oldsrc=0,oldpub=0,olddisp=0;
 for(;;){
  observation o=observe();uint64_t now=milliseconds();app_observed=o;
  demo_step(&state,&o,now);app_init_requests=state.init_requests;
  if(flags!=state.control){flags=state.control;exchange(0);}
  app_status=state.state==RUN_VIDEO?0x600d0011u:state.state;barrier();
  if(state.state==FAIL_LATCH){
   // No new frames; drain the current writer before recording final failure.
   // MM2S may repeat its last frame, and this is NOT permission to reconfigure.
   uint64_t end=milliseconds()+1000u;
   while(milliseconds()<end){uint32_t owners=exchange(9);if((owners&7)!=1 && ((owners>>3)&7)!=1)break;}
   halt(state.error,0);
  }
  if(now-last_window>=1000u){
   window_ms=(uint32_t)(now-last_window);window_source_eof=o.source_eof-oldsrc;
   window_published=o.published-oldpub;window_displayed=o.displayed-olddisp;
   oldsrc=o.source_eof;oldpub=o.published;olddisp=o.displayed;last_window=now;
  }
  uint64_t wake=milliseconds()+20u;while(milliseconds()<wake)__asm__ volatile("nop");
 }
}
