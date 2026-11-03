int main(void)
{
    unsigned n=0,cases=0;
#ifndef YOLO_HOST_TEST
    uart_init(CLK_HZ,BAUD);AI_BIAS=0;
#endif
    if(guards(&n)||n!=29)return 10;
#ifdef YOLO_HOST_TEST
    for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<8;++k){
        if(host_case(shape(k),k,seed))return 11;++cases;
    }
    for(unsigned k=0;k<144;++k){YoloLayer l=shape(0);l.ih=1+k%5;l.iw=1+(k*7)%19;
        l.pad=1+k%2;l.stride=1+(k/2)%2;l.ic=l.oc=l.groups=1+k%3;l.leaky=k%2;
        l.oh=(l.ih+2*l.pad-3)/l.stride+1;l.ow=(l.iw+2*l.pad-3)/l.stride+1;
        if(k%3==0&&l.oh>1)--l.oh;if(k%4==0&&l.ow>1)--l.ow;
        if(host_case(l,8,1+k%2))return 12;++cases;
    }
    // Probe precedes any new-interface write; the delegated old operator still
    // performs its normal legacy transport (also checked in actual RV32 RTL).
    YoloLayer l=shape(0);prepare(1);a31_model_reset(0);
    if(a31_control(&l,input+8,prior+8,weights+8,params)||
       a31_candidate(&l,input+8,actual+8,weights+8,params)||check(&l,0,1)||a31_words)return 13;
    prepare(1);a31_model_reset(2);
    if(a31_candidate(&l,input+8,actual+8,weights+8,params)!=AI_BLOCK_HW_ERROR||a31_words)return 14;
    // Busy before ownership causes no write. Timeout after ownership is bounded.
    a31_model_reset(4);
    if(a31_candidate(&l,input+8,actual+8,weights+8,params)!=AI_BLOCK_TIMEOUT)return 15;
    a31_model_reset(3);
    if(a31_candidate(&l,input+8,actual+8,weights+8,params)!=AI_BLOCK_HW_ERROR)return 16;
    printf("A31_HOST_ORACLE_PASS cases=%u guards=%u fallback_no_new_writes=PASS bounded_errors=PASS\n",cases,n);return 0;
#else
    for(unsigned k=0;k<(A31_SHORT?4u:8u);++k){YoloLayer l=shape(k);prepare(1);
        uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
        for(unsigned op=0;op<2;++op)if(run(op,&l))return 20;
        if(check(&l,k,1))return 21;
        for(unsigned sample=0;sample<3;++sample){uint64_t elapsed[2];
            for(unsigned i=0;i<2;++i){unsigned op=i^(sample&1);uint64_t t=rdcycle64();
                if(run(op,&l))return 22;elapsed[op]=rdcycle64()-t;}
            if(check(&l,k,1))return 23;
            uart_puts("A31_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
            field(" control",elapsed[0]);field(" candidate",elapsed[1]);uart_putc('\n');++cases;
        }
        if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 24;
    }
    uart_puts("A31_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_puts(" guards=");uart_putdec(n);uart_putc('\n');
    a31_result=1;return 0;
#endif
}
