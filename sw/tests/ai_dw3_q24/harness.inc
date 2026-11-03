/* Independent absolute-value/division Q24; all tested wide products fit int64. */
static int64_t scalar_wide(int32_t v,int32_t m)
{
 int64_t p=(int64_t)v*m,n=((p<0?-p:p)+8388608)/16777216;return p<0?-n:n;
}
static int pair(int32_t v,int32_t m,unsigned *wide,unsigned *narrow)
{
 int64_t q=scalar_wide(v,m);
 if(a30_wide_scale(v,m)!=q)return 1;++*wide;
 /* The original negative branch negates a narrowed int32 value. Compare it
  * only where that narrowing/negation is defined, not overflowing legacy UB. */
 if(q>=-INT32_MAX&&q<=INT32_MAX){
  if(a30_old_scale(v,m)!=(int32_t)q||a30_scale(v,m)!=(int32_t)q)return 2;++*narrow;
 }
 return 0;
}
static int scalar_tests(unsigned *wide,unsigned *narrow,unsigned *stores)
{
 const int32_t values[]={INT32_MIN,INT32_MIN+1,-1073741824,-16777217,-16777216,-8388609,-8388608,-8388607,-65537,-65536,-255,-129,-128,-127,-3,-1,0,1,3,127,128,129,255,65535,65536,65537,8388607,8388608,8388609,16777216,1073741823,INT32_MAX};
 const int32_t mult[]={INT32_MIN,INT32_MIN+1,-16777217,-16777216,-8388608,-16384,-1,0,1,256,16384,8388608,16777216,16777217,1073741824,INT32_MAX};
 *wide=*narrow=*stores=0;
 for(unsigned i=0;i<sizeof(values)/4;++i)for(unsigned j=0;j<sizeof(mult)/4;++j)
  if(pair(values[i],mult[j],wide,narrow))return 1;
 uint32_t rng=0x1234abcdu;
 for(unsigned i=0;i<2048;++i){rng=rng*1664525u+1013904223u;int32_t v=(int32_t)rng;
  rng=rng*1664525u+1013904223u;if(pair(v,(int32_t)rng,wide,narrow))return 2;}
 const int32_t a[]={-1048576,-255,-254,-253,-129,-128,-127,-3,-1,0,1,3,126,127,128,254,255,1048576};
 const int32_t m[]={-16777216,-8388608,-16384,0,16384,8388608,16777216},b[]={-128,-1,0,1,127};
 for(unsigned i=0;i<18;++i)for(unsigned j=0;j<7;++j)for(unsigned k=0;k<5;++k)
 for(unsigned leaky=0;leaky<2;++leaky)for(unsigned n=1;n<=8;++n){
  for(unsigned t=0;t<n;++t){int32_t v=(int32_t)scalar_wide(a[(i+t)%18],m[j])+b[k];
   if(leaky&&v<0)v=(int32_t)scalar_wide(v,1677722);
   if(v>127)v=127;if(v< -127)v=-127;
   if(a30_quant(a[(i+t)%18],m[j],b[k],leaky)!=v||a30_old_quant(a[(i+t)%18],m[j],b[k],leaky)!=v)return 3;
  }
  ++*stores;
 }
 return 0;
}
int main(void)
{
 unsigned n=0,cases=0,wide=0,narrow=0,stores=0;
#ifndef YOLO_HOST_TEST
 uart_init(CLK_HZ,BAUD);AI_BIAS=0;
#endif
 if(guards(&n)||scalar_tests(&wide,&narrow,&stores)||wide!=2560||stores!=10080)return 10;
#ifdef YOLO_HOST_TEST
 for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<8;++k){if(host_case(shape(k),k,seed))return 11;++cases;}
 for(unsigned k=0;k<144;++k){YoloLayer l=shape(0);l.ih=1+k%5;l.iw=1+(k*7)%19;
  l.pad=1+(k%2);l.stride=1+(k/2)%2;l.ic=l.oc=l.groups=1+k%3;l.leaky=k%2;
  l.oh=(l.ih+2*l.pad-3)/l.stride+1;l.ow=(l.iw+2*l.pad-3)/l.stride+1;
  if(k%3==0&&l.oh>1)--l.oh;if(k%4==0&&l.ow>1)--l.ow;
  if(host_case(l,8,1+k%2))return 12;++cases;
 }
 printf("A30_HOST_TRIPLE_ORACLE_PASS cases=%u guards=%u wide=%u narrow=%u stores=%u counts=PASS\n",cases,n,wide,narrow,stores);return 0;
#else
 uart_puts("A30_Q24_PASS wide=");uart_putdec(wide);uart_puts(" narrow=");uart_putdec(narrow);
 uart_puts(" stores=");uart_putdec(stores);uart_puts(" guards=");uart_putdec(n);uart_putc('\n');
 static const uint8_t order[6][3]={{0,1,2},{1,2,0},{2,0,1},{2,1,0},{1,0,2},{0,2,1}};
 for(unsigned k=0;k<(A30_SHORT?2u:8u);++k){YoloLayer l=shape(k);prepare(1);
  uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
  for(unsigned op=0;op<3;++op)if(run(op,&l))return 20;
  if(check(&l,k,1))return 21;
  for(unsigned sample=0;sample<(A30_SHORT?1u:6u);++sample){uint64_t elapsed[3];
   for(unsigned i=0;i<3;++i){unsigned op=order[sample][i];uint64_t t=rdcycle64();
    if(run(op,&l))return 22;elapsed[op]=rdcycle64()-t;}
   if(check(&l,k,1))return 23;
   uart_puts("A30_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
   field(" control",elapsed[0]);field(" placebo",elapsed[1]);field(" candidate",elapsed[2]);uart_putc('\n');++cases;
  }
  if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 24;
 }
 uart_puts("A30_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_putc('\n');a30_result=1;return 0;
#endif
}
