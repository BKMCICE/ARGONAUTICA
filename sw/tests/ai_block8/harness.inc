static int guards(unsigned *count)
{
    YoloLayer l=shape(0),v;prepare(1);*count=0;
#ifdef YOLO_HOST_TEST
    a33_reset(0);
#endif
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
#define BAD(a,b,c,d,e) do{if(a33_control(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE||a33_candidate(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE)return 1;++*count;}while(0)
    BAD(0,input+8,actual+8,weights+8,params);BAD(&l,0,actual+8,weights+8,params);
    BAD(&l,input+8,0,weights+8,params);BAD(&l,input+8,actual+8,0,params);BAD(&l,input+8,actual+8,weights+8,0);
#define FIELD(n,value) do{v=l;v.n=value;BAD(&v,input+8,actual+8,weights+8,params);}while(0)
    FIELD(kind,2);FIELD(size,3);FIELD(groups,0);FIELD(groups,3);FIELD(stride,0);FIELD(pad,1);
    FIELD(ih,0);FIELD(iw,0);FIELD(oh,0);FIELD(ow,0);FIELD(ic,0);FIELD(oc,0);
    FIELD(ic,225);FIELD(oh,3);FIELD(ow,10);FIELD(ih,UINT32_MAX);FIELD(oc,UINT32_MAX);
    BAD(&l,input+8,input+8,weights+8,params);BAD(&l,input+8,weights+8,weights+8,params);
    BAD(&l,input+8,(int8_t *)params,weights+8,params);BAD(&l,input+8,(int8_t *)&l,weights+8,params);
    const void *end=(const void *)(UINTPTR_MAX-3);
    BAD(&l,end,actual+8,weights+8,params);BAD(&l,input+8,(int8_t *)end,weights+8,params);
    BAD(&l,input+8,actual+8,end,params);BAD(&l,input+8,actual+8,weights+8,end);
    void *scratch=a33_scratch();
    BAD(&l,scratch,actual+8,weights+8,params);BAD(&l,input+8,scratch,weights+8,params);
    BAD(&l,input+8,actual+8,scratch,params);BAD(&l,input+8,actual+8,weights+8,scratch);
#undef FIELD
#undef BAD
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 2;
#ifdef YOLO_HOST_TEST
    if(a33_reads||a33_writes)return 3;
#endif
    return 0;
}
#ifdef YOLO_HOST_TEST
static int oracle(const YoloLayer *l)
{
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow,ci=l->ic/l->groups,co=l->oc/l->groups;
    for(uint32_t o=0;o<l->oc;++o)for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;++x){
        int64_t dot=0;
        for(uint32_t c=0;c<ci;++c)dot+=(int32_t)input[8+((o/co)*ci+c)*plane+y*l->stride*l->iw+x*l->stride]*weights[8+o*ci+c];
        if(actual[8+(o*l->oh+y)*l->ow+x]!=quantize((int32_t)dot,params[2*o],params[2*o+1],l->leaky))return 1;
    }return 0;
}
static int host_case(YoloLayer l,unsigned k,unsigned seed)
{
    prepare(seed);a33_reset(0);
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
    if(a33_control(&l,input+8,prior+8,weights+8,params))return 1;
    uint32_t ctrl_tasks=a33_starts,ctrl_weights=a33_weight_words,ctrl_pixels=a33_pixel_words,raw=a33_raw_reads;
    a33_reset(0);if(a33_candidate(&l,input+8,actual+8,weights+8,params))return 2;
    if(oracle(&l)||check(&l,k,seed))return 3;
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 4;
    unsigned ci=l.ic/l.groups,co=l.oc/l.groups,blocks=(ci+8)/9;
    unsigned ctrl_batches=l.groups*((co+3)/4),new_batches=l.groups*((co+7)/8);
    if(ctrl_tasks!=ctrl_batches*l.oh*((l.ow+7)/8)||a33_starts!=new_batches*l.oh*((l.ow+7)/8)||
       ctrl_weights!=l.oc*blocks*3||a33_weight_words!=ctrl_weights||
       ctrl_pixels!=ctrl_batches*l.oh*l.ow*blocks*3||a33_pixel_words!=new_batches*l.oh*l.ow*blocks*3||
       raw!=l.oc*l.oh*l.ow||a33_raw_reads!=raw)return 5;
    return 0;
}
#else
static void field(const char *name,uint64_t value){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(value>>32));uart_puthex((uint32_t)value);}
static int run(unsigned op,const YoloLayer *l)
{
    a33_phase=op+1;
    int rc=op?a33_candidate(l,input+8,actual+8,weights+8,params):a33_control(l,input+8,prior+8,weights+8,params);
    a33_phase=0;return rc;
}
#endif
int main(void)
{
    unsigned guard_count=0,cases=0;
#ifndef YOLO_HOST_TEST
    uart_init(CLK_HZ,BAUD);AI_BIAS=0;
    uint32_t actual_block8_id=AI_BLOCK_READ(0x28u);
    uart_puts("A33_BLOCK8_ID=0x");uart_puthex(actual_block8_id);uart_putc('\n');
#endif
    if(guards(&guard_count))return 10;
#ifdef YOLO_HOST_TEST
    for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<11;++k){if(host_case(shape(k),k,seed))return 11;++cases;}
    for(unsigned k=0;k<144;++k){YoloLayer l=shape(0);l.groups=1+k%2;l.stride=1+(k/2)%2;
        l.ih=1+k%5;l.iw=1+(k*7)%19;l.oh=(l.ih-1)/l.stride+1;l.ow=(l.iw-1)/l.stride+1;
        const unsigned ci[]={1,8,9,10,16,17,224};l.ic=ci[k%7]*l.groups;l.oc=(1+(k*3)%11)*l.groups;l.leaky=k%2;
        if(host_case(l,11,1+k%2))return 12;++cases;
    }
    YoloLayer crop=shape(4);crop.oh=2;crop.ow=3;if(host_case(crop,11,1))return 13;++cases;
    YoloLayer l=shape(0);prepare(1);a33_reset(7);
    if(a33_control(&l,input+8,prior+8,weights+8,params))return 14;
    a33_reset(7);if(a33_candidate(&l,input+8,actual+8,weights+8,params)||check(&l,0,1))return 15;
    const unsigned boundary_ci[]={1,3,4,8,9,10,16,17,120,224,2};
    const unsigned boundary_co[]={1,3,4,5,7,8,9,16,24};
    for(unsigned a=0;a<11;++a)for(unsigned b=0;b<9;++b){
        YoloLayer edge=shape(0);edge.groups=1+(a+b)%2;edge.ic=boundary_ci[a]*edge.groups;
        edge.oc=boundary_co[b]*edge.groups;edge.ih=2;edge.iw=17;edge.oh=2;edge.ow=17;
        edge.leaky=(a+b)%2;if(host_case(edge,11,1))return 24;++cases;
    }
    for(unsigned mode=1;mode<=6;++mode){prepare(1);a33_reset(mode);
        int want=mode==1?AI_BLOCK_UNSUPPORTED:mode==3||mode==6?AI_BLOCK_TIMEOUT:AI_BLOCK_HW_ERROR;
        if(a33_candidate(&l,input+8,actual+8,weights+8,params)!=want)return 16;
        if((mode==1||mode==2)&&a33_writes)return 17;
        if(a33_starts!=(mode==1||mode==2?0:mode==6?2:1))return 18;
        if(mode<=4)for(unsigned i=0;i<sizeof(actual);++i)if(actual[i]!=0x5a)return 19;
    }
    printf("A33_HOST_ORACLE_PASS cases=%u guards=%u errors=6 old_fallback=PASS counters_readonly_sentinels=PASS\n",cases,guard_count);return 0;
#else
    for(unsigned k=0;k<11;++k){YoloLayer l=shape(k);prepare(1);
        uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
        if(run(0,&l)||run(1,&l)||check(&l,k,1))return 20;
        for(unsigned sample=0;sample<3;++sample){uint64_t elapsed[2];
            for(unsigned i=0;i<2;++i){unsigned op=i^(sample&1);uint64_t t=rdcycle64();
                if(run(op,&l))return 21;elapsed[op]=rdcycle64()-t;}
            if(check(&l,k,1))return 22;
            uart_puts("A33_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
            field(" control",elapsed[0]);field(" candidate",elapsed[1]);uart_putc('\n');++cases;
        }
        if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 23;
    }
    uart_puts("A33_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_puts(" guards=");uart_putdec(guard_count);uart_putc('\n');
    a33_result=1;return 0;
#endif
}
