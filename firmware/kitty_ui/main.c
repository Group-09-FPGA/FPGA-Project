#include <stdint.h>

void *memcpy(void *dst,const void *src,unsigned n) {
    unsigned char *d=dst;const unsigned char *s=src;
    for(unsigned i=0;i<n;i++) d[i]=s[i];
    return dst;
}

// All numerical state and rows are read from live FPGA registers and RAM.
// Static strings below are labels and keyboard help, never demonstration data.
#define UI ((volatile uint32_t *)0x10000000u)
#define QUERY_CMD (*(volatile uint32_t *)0x10000100u)
#define FRONT_BANK (*(volatile uint32_t *)0x10000104u)
#define PRESENT (*(volatile uint32_t *)0x10000108u)
#define QUERY_DATA ((volatile uint32_t *)0x10000200u)
#define CELL ((volatile uint32_t *)0x30000000u)
#define PLOT ((volatile uint32_t *)0x40000000u)
#define COLS 160
#define ROWS 45
#define FG 0
#define GREEN 1
#define RED 2
#define DIM 3
#define PURPLE 4
#define GOLD 5
#define BLUE 10
#define ORANGE 11
#define BG 8
#define SELECTED 7

static uint32_t words[19];
static uint32_t cached[64];
static uint32_t bid_values[128], ask_values[128], event_numbers[128];
static uint32_t scale_low, scale_high;
static char buf[100];
static int bn;
static int quote_n;
static int bank;

static void cell(int x,int y,char c,int fg,int bg) {
    if(x>=0 && x<COLS && y>=0 && y<ROWS)
        CELL[bank*8192+y*COLS+x]=(uint32_t)(((bg<<4)|fg)<<8)|(uint8_t)c;
}
static void text(int x,int y,const char *s,int fg) {
    while(*s && x<COLS) cell(x++,y,*s++,fg,BG);
}
static void stripe(int y,int bg) {
    for(int x=0;x<COLS;x++) cell(x,y,' ',FG,bg);
}
static void highlight(int x,int y,const char *s) {
    for(;*s && x<COLS;x++,s++) cell(x,y,*s,FG,SELECTED);
}
static void clear_screen(void) {
    for(int i=0;i<ROWS*COLS;i++) CELL[bank*8192+i]=0x8020;
}
static void decimal(char *out,uint32_t value) {
    char reversed[10];int n=0;
    do {reversed[n++]=(char)('0'+value%10);value/=10;} while(value && n<10);
    for(int i=0;i<n;i++) out[i]=reversed[n-i-1];
    out[n]=0;
}
static void hex32(char *out,uint32_t value,int digits) {
    const char *hex="0123456789ABCDEF";
    for(int i=0;i<digits;i++) out[i]=hex[(value>>((digits-i-1)*4))&15];
    out[digits]=0;
}
static void hex64(char *out,uint32_t low,uint32_t high) {
    hex32(out,high,8);hex32(out+8,low,8);
}
static void money(char *out,uint32_t price) {
    char whole[11];decimal(whole,price/10000);
    int i=0;while(whole[i]) {out[i]=whole[i];i++;}
    out[i++]='.';
    uint32_t frac=price%10000;
    out[i++]=(char)('0'+frac/1000);
    out[i++]=(char)('0'+frac/100%10);
    out[i++]=(char)('0'+frac/10%10);
    out[i++]=(char)('0'+frac%10);out[i]=0;
}
static void money2(char *out,uint32_t price) {
    uint32_t cents=(price+50)/100;
    char whole[11];decimal(whole,cents/100);
    int i=0;while(whole[i]) {out[i]=whole[i];i++;}
    out[i++]='.';out[i++]=(char)('0'+cents/10%10);out[i++]=(char)('0'+cents%10);out[i]=0;
}
static void b_reset(void) {bn=0;buf[0]=0;}
static void b_str(const char *s) {while(*s && bn<98) buf[bn++]=*s++;buf[bn]=0;}
static void b_dec(uint32_t v) {char t[12];decimal(t,v);b_str(t);}
static void b_money(uint32_t v) {char t[24];money(t,v);b_str("$");b_str(t);}
static void b_money2(uint32_t v) {char t[24];money2(t,v);b_str("$");b_str(t);}
static void b_id(uint32_t lo,uint32_t hi) {
    char t[17];hex64(t,lo,hi);int i=0;
    while(t[i]=='0' && i<15) i++;
    b_str("#");b_str(t+i);
}
static void label_u(int x,int y,const char *name,uint32_t v,int color) {
    char s[12];text(x,y,name,DIM);decimal(s,v);text(x+22,y,s,color);
}
static void label_hex(int x,int y,const char *name,uint32_t v) {
    char s[9];text(x,y,name,DIM);hex32(s,v,8);text(x+22,y,s,FG);
}
static void query(int kind,int addr,int count) {
    QUERY_CMD=(uint32_t)((kind<<16)|addr);
    for(int i=0;i<count;i++) words[i]=QUERY_DATA[i];
}
static uint32_t bits(int lo,int count) {
    int word=lo>>5,shift=lo&31;
    uint32_t v=words[word]>>shift;
    if(shift && word<18) v|=words[word+1]<<(32-shift);
    if(count<32) v&=(1u<<count)-1;
    return v;
}
static void header(const char *page,const char *help) {
    stripe(0,9);
    highlight(2,0," LIVE ORDER BOOK ");
    text(21,0,"/",DIM);text(24,0,page,PURPLE);
    text(130,0,"FPGA LIVE",GREEN);
    stripe(43,9);
    int p=(int)(cached[0]&15);
    static const char *const names[6]={"1 Market","2 My Orders","3 Hash Table","4 Event Log",
        "5 Price Levels","6 Order Slots"};
    static const int pages[6]={0,1,2,3,5,6};
    int x=2;
    for(int i=0;i<6;i++) {
        if(pages[i]==p) highlight(x,43,names[i]);else text(x,43,names[i],FG);
        for(const char *c=names[i];*c;c++) x++;
        x+=3;
    }
    text(2,44,help,DIM);
}
static void plot_point(int chart,int x,int y,int last_y) {
    if(x<0 || x>=512 || y<0 || y>=256) return;
    int lo=y<last_y?y:last_y,hi=y>last_y?y:last_y;
    uint32_t word=(uint32_t)y | ((uint32_t)lo<<9) | ((uint32_t)hi<<18);
    PLOT[bank*2048+chart*512+x]=word;
}
static int y_of(uint32_t v) {
    return 255-(int)(((uint64_t)(v-scale_low)*255)/(scale_high-scale_low));
}
static void draw_line(int chart,const uint32_t *values,int count) {
    for(int x=0;x<512;x++) PLOT[bank*2048+chart*512+x]=0x1fffffff;
    int previous=-1,previous_y=0;
    for(int i=0;i<count;i++) if(values[i]) {
        int x=count==1?511:i*511/(count-1);
        int y=y_of(values[i]);
        if(previous>=0) {
            for(int k=previous+1;k<x;k++) plot_point(chart,k,previous_y,previous_y);
            plot_point(chart,x,y,previous_y);
        } else plot_point(chart,x,y,y);
        previous=x;previous_y=y;
    }
}
// One shared price scale so the bid and ask lines are drawn on the same axis.
static int draw_graph(int count) {
    uint32_t low=0xffffffffu,high=0;
    for(int i=0;i<count;i++) {
        if(bid_values[i]) {if(bid_values[i]<low) low=bid_values[i];if(bid_values[i]>high) high=bid_values[i];}
        if(ask_values[i]) {if(ask_values[i]<low) low=ask_values[i];if(ask_values[i]>high) high=ask_values[i];}
    }
    for(int c=0;c<4;c++) for(int x=0;x<512;x++) PLOT[bank*2048+c*512+x]=0x1fffffff;
    if(low==0xffffffffu) return 0;
    if(high==low) {high+=1000;low=low>1000?low-1000:0;}
    else {uint32_t pad=(high-low)/8+1;high+=pad;low=low>pad?low-pad:0;}
    scale_low=low;scale_high=high;
    draw_line(0,bid_values,count);draw_line(1,ask_values,count);
    return 1;
}
// Long history kept by this CPU (the FPGA journal only holds the last 128 changes).
// One point is saved every `hist_stride` events; when the buffer fills, every other
// point is dropped and the stride doubles, so it always spans the whole session.
#define HIST 512
static uint32_t hist_mid[HIST],hist_event[HIST],hist_stride=2,hist_last;
static int hist_n;
static uint32_t ov_low,ov_high;
static void record_history(void) {
    uint32_t ev=cached[21];
    // The event count restarts at 0 when the board is reset: forget the old session.
    // (CPU RAM is not cleared by a reset, so this must be done explicitly.)
    if(ev<hist_last || ev==0) {hist_n=0;hist_stride=2;hist_last=0;}
    if((cached[15]&6)!=6) return;
    if(hist_n && ev-hist_last<hist_stride) return;
    if(hist_n==HIST) {
        for(int i=0;i<HIST/2;i++) {hist_mid[i]=hist_mid[2*i];hist_event[i]=hist_event[2*i];}
        hist_n=HIST/2;hist_stride*=2;
    }
    hist_mid[hist_n]=(cached[16]+cached[18])/2;hist_event[hist_n]=ev;hist_n++;hist_last=ev;
}
static int ov_y(uint32_t v) {
    return 159-(int)(((uint64_t)(v-ov_low)*159)/(ov_high-ov_low));
}
// The whole session squeezed into one small picture (bottom right of the Market page).
static void overview(void) {
    int n=hist_n;
    text(92,31,"OVERVIEW: THE WHOLE SESSION IN ONE PICTURE",PURPLE);
    if(n<2) {text(100,36,"collecting data...",DIM);return;}
    uint32_t low=0xffffffffu,high=0;
    for(int i=0;i<n;i++) {
        if(hist_mid[i]<low) low=hist_mid[i];
        if(hist_mid[i]>high) high=hist_mid[i];
    }
    if(high==low) {high+=1000;low=low>1000?low-1000:0;}
    else {uint32_t pad=(high-low)/10+1;high+=pad;low=low>pad?low-pad:0;}
    ov_low=low;ov_high=high;
    int previous=-1,previous_y=0;
    for(int i=0;i<n;i++) {
        int x=i*511/(n-1),y=ov_y(hist_mid[i]);
        if(previous>=0) {
            for(int k=previous+1;k<x;k++) plot_point(2,k,previous_y,previous_y);
            plot_point(2,x,y,previous_y);
        } else plot_point(2,x,y,y);
        previous=x;previous_y=y;
    }
    for(int k=0;k<5;k++) {
        int row=k==0?32:32+k*2;
        uint32_t v=high-(uint32_t)(((uint64_t)(k==0?0:k*32)*(high-low))/159);
        b_reset();b_money2(v);text(93-bn,row,buf,DIM);
    }
    b_reset();b_str("event ");b_dec(hist_event[0]);text(94,42,buf,DIM);
    b_reset();b_str("event ");b_dec(hist_event[n-1]);text(159-bn,42,buf,DIM);
    text(108,42,"price over time ->",DIM);
}
static void load_quotes(void) {
    uint32_t meta=cached[32];
    int available=(int)(meta&255),offset=(int)cached[14];
    if(offset>=available) offset=available?available-1:0;
    quote_n=available-offset;if(quote_n>64) quote_n=64;
    int next=(int)((meta>>8)&127);
    for(int i=0;i<quote_n;i++) {
        int addr=(next-offset-quote_n+i)&127;
        query(7,addr,6);
        bid_values[i]=bits(141,32);
        ask_values[i]=bits(76,32);
        if(!bits(173,1)) bid_values[i]=0;
        if(!bits(108,1)) ask_values[i]=0;
        event_numbers[i]=bits(0,32);
    }
}
static int chart_row(uint32_t value) {
    int row=(96+2*y_of(value))/16;
    return row<6?6:row>31?31:row;
}
static void market(void) {
    header("MARKET","H = every past price   Up/Down or PgUp/PgDn = scroll back in time   1-6 = switch page");
    char s[24];
    int bid_ok=cached[15]&2,ask_ok=cached[15]&4;
    text(2,2,"BEST BUY PRICE (BID)",BLUE);text(34,2,"BEST SELL PRICE (ASK)",ORANGE);text(66,2,"SPREAD (THE GAP)",FG);
    if(bid_ok) {money(s,cached[16]);text(2,3,s,BLUE);} else text(2,3,"no buyers yet",DIM);
    if(ask_ok) {money(s,cached[18]);text(34,3,s,ORANGE);} else text(34,3,"no sellers yet",DIM);
    if(bid_ok && ask_ok && cached[18]>=cached[16]) {money(s,cached[18]-cached[16]);text(66,3,s,FG);}
    else text(66,3,"--",DIM);
    text(2,4,"^ highest price a buyer offers",DIM);
    text(34,4,"^ lowest price a seller accepts",DIM);
    text(66,4,"^ ask minus bid",DIM);

    load_quotes();
    text(4,5,"PRICE ($)",DIM);
    int have=draw_graph(quote_n);
    if(have) {
        for(int k=0;k<8;k++) {
            int idx=4+32*k;
            uint32_t value=scale_high-(uint32_t)(((uint64_t)idx*(scale_high-scale_low))/255);
            b_reset();b_money2(value);
            text(12-bn,6+4*k,buf,DIM);
        }
        if(quote_n>1) {
            uint32_t first=event_numbers[0],last=event_numbers[quote_n-1];
            for(int j=0;j<=8;j++) {
                b_reset();b_dec(first+(uint32_t)(((uint64_t)(last-first)*j)/8));
                int x=13+8*j-bn/2;if(x<0) x=0;
                text(x,39,buf,DIM);
            }
        }
        // Arrows from the labels to the end of each line.
        int last=quote_n-1;
        int brow=-1,arow=-1;
        if(bid_values[last]) brow=chart_row(bid_values[last]);
        if(ask_values[last]) arow=chart_row(ask_values[last]);
        if(brow==arow && brow>=0) {if(arow>6) arow--;else brow++;}
        if(brow>=0) {b_reset();b_str("<-- BID ");b_money2(bid_values[last]);text(77,brow,buf,BLUE);}
        if(arow>=0) {b_reset();b_str("<-- ASK ");b_money2(ask_values[last]);text(77,arow,buf,ORANGE);}
    } else text(20,20,"Waiting for the first orders to draw the graph...",DIM);
    text(30,40,"EVENT NUMBER  (older  ->  newer)",DIM);
    text(13,41,"BLUE",BLUE);text(18,41,"= best buy price   ",DIM);
    text(36,41,"ORANGE",ORANGE);text(43,41,"= best sell price   shaded band = spread",DIM);

    int x=92;
    text(x,6,"WHAT AM I LOOKING AT?",PURPLE);
    text(x,8,"A market matches buyers with sellers.",FG);
    text(x,9,"Buyers say the highest price they will pay (BID).",FG);
    text(x,10,"Sellers say the lowest price they will take (ASK).",FG);
    text(x,11,"A trade can only happen when the two meet.",FG);
    text(x,13,"RIGHT NOW",PURPLE);
    if(bid_ok) {b_reset();b_str("Buyers will pay up to ");b_money(cached[16]);text(x,14,buf,BLUE);}
    else text(x,14,"There are no buyers in the book.",DIM);
    if(ask_ok) {b_reset();b_str("Sellers want at least ");b_money(cached[18]);text(x,15,buf,ORANGE);}
    else text(x,15,"There are no sellers in the book.",DIM);
    if(bid_ok && ask_ok && cached[18]>=cached[16]) {
        b_reset();b_str("The gap between them is ");b_money(cached[18]-cached[16]);text(x,16,buf,FG);
    }
    text(x,18,"ON THE GRAPH",PURPLE);
    text(x,19,"<-- Each step is an order arriving, changing or leaving.",FG);
    text(x,20,"<-- Blue line: best buy price over time.",BLUE);
    text(x,21,"<-- Orange line: best sell price over time.",ORANGE);
    text(x,22,"<-- Shaded band between them: the spread.",DIM);
    text(x,24,"THE BOOK",PURPLE);
    b_reset();b_str("Orders waiting: ");b_dec(cached[20]);text(x,25,buf,FG);
    b_reset();b_str("Events processed: ");b_dec(cached[21]);text(x,26,buf,FG);
    if(cached[14]) {
        b_reset();b_str("Viewing history: ");b_dec(cached[14]);b_str(" samples back (PgDn = newer)");
        text(x,28,buf,GOLD);
    }
    if(!(cached[15]&1)) text(x,29,"BOOK INVALID: an order was rejected. Reset the board.",RED);
    overview();
}
static void explain(int x,int y,const char *title,const char *a,const char *b,const char *c,const char *d) {
    text(x,y,title,PURPLE);
    if(a) text(x,y+2,a,FG);
    if(b) text(x,y+3,b,FG);
    if(c) text(x,y+4,c,DIM);
    if(d) text(x,y+5,d,DIM);
}
static void history(void) {
    header("PRICE HISTORY","Up/Down or PgUp/PgDn = scroll   1-6 = leave this page");
    text(2,2,"EVENT #               BEST BUY (BID)         BEST SELL (ASK)",DIM);
    uint32_t meta=cached[32];int count=(int)(meta&255),next=(int)((meta>>8)&127);
    int offset=(int)cached[14];
    for(int row=0;row<38 && row+offset<count;row++) {
        query(7,(next-1-offset-row)&127,6);
        char s[24];int y=row+4;
        decimal(s,bits(0,32));text(2,y,s,FG);
        if(bits(173,1)) {money(s,bits(141,32));text(24,y,s,GREEN);}
        if(bits(108,1)) {money(s,bits(76,32));text(48,y,s,RED);}
    }
    explain(96,4,"WHAT AM I LOOKING AT?","Every time the best buy or sell price changes,","the board saves one line here (newest first).","<-- Left: the event number when it changed.","Press 1 to go back to the graph.");
}
static int set_used(int set) {
    static const uint8_t word[8]={2,4,7,9,11,14,16,18};
    static const uint8_t shift[8]={11,23,3,15,27,7,19,31};
    QUERY_CMD=(uint32_t)((2<<16)|set);
    int n=0;
    for(int w=0;w<8;w++) n+=(int)((QUERY_DATA[word[w]]>>shift[w])&1);
    return n;
}
static void hash_page(void) {
    header("HASH TABLE","Arrows = move the selected square   Tab = pick a way   PgUp/PgDn = jump 256 sets");
    int set=cached[11]&1023,sel_way=(cached[11]>>10)&7;
    char s[24];
    text(2,2,"ALL 1024 SETS",PURPLE);
    text(8,3,"0 . . . 4 . . . 8 . . .12 . . .16 . . .20 . . .24 . . .28 . . .",DIM);
    for(int row=0;row<32;row++) {
        decimal(s,row*32);text(2,4+row,s,DIM);
        for(int col=0;col<32;col++) {
            int index=row*32+col,n=set_used(index);
            char c=n?(char)('0'+n):'.';
            if(index==set) {cell(8+col*2,4+row,c,FG,SELECTED);cell(9+col*2,4+row,' ',FG,SELECTED);}
            else cell(8+col*2,4+row,c,n?(n==8?ORANGE:GREEN):DIM,BG);
        }
    }
    text(2,37,"Each square is one set. The digit is how many of its 8 ways hold an order",DIM);
    text(2,38,"(. = empty, 8 = full). The highlighted square is shown on the right.",DIM);
    text(2,39,"Set number = row number + column (row label is the first set of that row).",DIM);

    int x=80;
    b_reset();b_str("SELECTED SET ");b_dec((uint32_t)set);text(x,2,buf,PURPLE);
    text(x,3,"An order ID is hashed to pick a set. Each set has 8 ways (slots).",DIM);
    text(x,5,"WAY",DIM);text(x+6,5,"USED?",DIM);text(x+14,5,"ORDER ID",DIM);
    text(x+34,5,"SIDE",DIM);text(x+41,5,"PRICE ($)",DIM);text(x+53,5,"SHARES",DIM);
    query(2,set,19);
    uint32_t id_lo[8],id_hi[8],slots[8];int used[8];
    for(int way=0;way<8;way++) {
        int bit=way*76;
        used[way]=(int)bits(bit+75,1);slots[way]=bits(bit+64,11);
        id_lo[way]=bits(bit,32);id_hi[way]=bits(bit+32,32);
    }
    for(int way=0;way<8;way++) {
        int y=7+way*3;
        char tag[4]={' ',(char)('0'+way),' ',0};
        if(way==sel_way) highlight(x,y,tag);else text(x,y,tag,FG);
        text(x+6,y,used[way]?"YES":"NO",used[way]?GREEN:DIM);
        if(used[way]) {
            char id[17];hex64(id,id_lo[way],id_hi[way]);text(x+14,y,id,FG);
            query(1,(int)slots[way],2);
            text(x+34,y,bits(45,1)?"SELL":"BUY",bits(45,1)?ORANGE:BLUE);
            money(s,cached[30]+bits(32,13)*cached[31]);text(x+41,y,s,FG);
            decimal(s,bits(0,32));text(x+53,y,s,FG);
        } else text(x+14,y,"(free)",DIM);
    }
    text(x,32,"COLLISION STASH (orders that did not fit in their set)",PURPLE);
    int shown=0;
    for(int index=0;index<8;index++) {
        query(3,index,3);
        if(bits(75,1)) {
            char id[17];hex64(id,bits(0,32),bits(32,32));
            if(shown<4) text(x,34+shown,id,FG);
            shown++;
        }
    }
    if(!shown) text(x,34,"empty",DIM);
}
static void events_page(void) {
    header("EVENT LOG","Up/Down = scroll   PgUp/PgDn = next screen");
    text(2,2,"EVENT #   WHAT HAPPENED      ORDER ID",DIM);
    uint32_t meta=cached[32];int count=(int)((meta>>15)&511),next=(int)((meta>>24)&255);
    int offset=(int)cached[14];
    for(int row=0;row<38 && row+offset<count;row++) {
        query(8,(next-1-offset-row)&255,13);
        char s[24],id[17];int y=row+4;
        decimal(s,bits(362,32));text(2,y,s,FG);
        int op=bits(311,4);
        static const char *const kinds[6]={"?","Order added","Order traded","Order cancelled","Order deleted","Order replaced"};
        text(12,y,kinds[op<6?op:0],op==1?GREEN:op==4?ORANGE:GOLD);
        hex64(id,bits(247,32),bits(279,32));text(30,y,id,FG);
    }
    explain(60,4,"WHAT AM I LOOKING AT?","A log of every change the order book has finished,","newest at the top.","<-- Added: a new buy or sell order arrived.","<-- Traded / cancelled / deleted / replaced: it changed.");
    text(2,42,"Each row is a real record stored by the FPGA.",DIM);
}
static void grid_header(int x,int y,int cols) {
    for(int c=0;c<cols;c+=4) {
        char t[4];decimal(t,(uint32_t)c);text(x+c*(cols==32?2:1),y,t,DIM);
    }
}
static void levels_page(void) {
    header("PRICE LEVELS","Arrows = move the selected square   PgUp/PgDn = jump 256 squares");
    int sel=cached[13]&1023;
    text(2,2,"ALL 8192 PRICE STEPS  (one square = 8 steps)",PURPLE);
    grid_header(8,3,32);
    for(int row=0;row<32;row++) {
        char s[24];decimal(s,(uint32_t)(row*256));text(2,4+row,s,DIM);
        for(int col=0;col<32;col++) {
            int bucket=row*32+col,mask=0;
            for(int l=0;l<8;l++) {
                int idx=bucket*8+l;
                QUERY_CMD=(uint32_t)((4<<16)|idx);if(QUERY_DATA[0]) mask|=1;
                QUERY_CMD=(uint32_t)((4<<16)|(8192+idx));if(QUERY_DATA[0]) mask|=2;
            }
            char c=mask==0?'.':mask==1?'B':mask==2?'S':'X';
            int color=mask==0?DIM:mask==1?BLUE:mask==2?ORANGE:GOLD;
            if(bucket==sel) {cell(8+col*2,4+row,c,FG,SELECTED);cell(9+col*2,4+row,' ',FG,SELECTED);}
            else cell(8+col*2,4+row,c,color,BG);
        }
    }
    text(2,37,"B = buyers waiting   S = sellers waiting   X = both   . = nothing",DIM);
    text(2,38,"The highlighted square is shown on the right. Row label = first step in the row.",DIM);
    text(2,39,"Price of a step = base price + step number x tick size.",DIM);

    int x=80;
    b_reset();b_str("SELECTED SQUARE ");b_dec((uint32_t)sel);b_str("  (steps ");
    b_dec((uint32_t)(sel*8));b_str(" to ");b_dec((uint32_t)(sel*8+7));b_str(")");
    text(x,2,buf,PURPLE);
    text(x,3,"Each step is one possible price. It lists the shares waiting there.",DIM);
    text(x,5,"STEP",DIM);text(x+8,5,"PRICE ($)",DIM);text(x+22,5,"BUY SHARES",BLUE);
    text(x+36,5,"BUY ORDERS",BLUE);text(x+50,5,"SELL SHARES",ORANGE);text(x+64,5,"SELL ORDERS",ORANGE);
    for(int l=0;l<8;l++) {
        int idx=sel*8+l,y=7+l*3;
        char s[24];
        decimal(s,(uint32_t)idx);text(x,y,s,FG);
        money(s,cached[30]+(uint32_t)idx*cached[31]);text(x+8,y,s,FG);
        query(4,idx,1);uint32_t bq=words[0];
        query(6,idx,1);uint32_t bo=words[0]&4095;
        query(4,8192+idx,1);uint32_t aq=words[0];
        query(6,8192+idx,1);uint32_t ao=words[0]&4095;
        decimal(s,bq);text(x+22,y,s,bq?BLUE:DIM);
        decimal(s,bo);text(x+36,y,s,bo?BLUE:DIM);
        decimal(s,aq);text(x+50,y,s,aq?ORANGE:DIM);
        decimal(s,ao);text(x+64,y,s,ao?ORANGE:DIM);
    }
    text(x,32,"WHAT AM I LOOKING AT?",PURPLE);
    text(x,34,"The book keeps one row per possible price. A row with shares means",FG);
    text(x,35,"people are waiting to buy (blue) or sell (orange) at that price.",FG);
}
static void slots_page(void) {
    header("ORDER SLOTS","Arrows = move the selected square   PgUp/PgDn = jump 512 slots");
    int sel=cached[12]&2047,used_total=0;
    text(2,2,"ALL 2048 ORDER SLOTS  (one square = one slot)",PURPLE);
    grid_header(8,3,64);
    for(int row=0;row<32;row++) {
        char s[24];decimal(s,(uint32_t)(row*64));text(2,4+row,s,DIM);
        for(int col=0;col<64;col++) {
            int slot=row*64+col;
            QUERY_CMD=(uint32_t)((1<<16)|slot);
            uint32_t w1=QUERY_DATA[1];
            int used=(int)((w1>>14)&1),sell=(int)((w1>>13)&1);
            used_total+=used;
            char c=used?(sell?'S':'B'):'.';
            if(slot==sel) cell(8+col,4+row,c,FG,SELECTED);
            else cell(8+col,4+row,c,used?(sell?ORANGE:BLUE):DIM,BG);
        }
    }
    text(2,37,"B = slot holds a buy order   S = holds a sell order   . = free",DIM);
    text(2,38,"The highlighted square is shown on the right. Row label = first slot in the row.",DIM);

    int x=80;
    b_reset();b_str("SLOTS ");b_dec((uint32_t)(sel&~7));b_str(" TO ");b_dec((uint32_t)((sel&~7)+7));
    b_str("  (selected: ");b_dec((uint32_t)sel);b_str(")");
    text(x,2,buf,PURPLE);
    b_reset();b_str("Slots in use: ");b_dec((uint32_t)used_total);b_str(" of 2048");text(x,3,buf,GREEN);
    text(x,5,"SLOT",DIM);text(x+8,5,"IN USE?",DIM);text(x+18,5,"SIDE",DIM);
    text(x+26,5,"PRICE ($)",DIM);text(x+40,5,"SHARES LEFT",DIM);
    for(int k=0;k<8;k++) {
        int slot=(sel&~7)+k,y=7+k*3;
        char s[24];
        query(1,slot,2);
        int used=(int)bits(46,1),sell=(int)bits(45,1);
        decimal(s,(uint32_t)slot);
        if(slot==sel) highlight(x,y,s);else text(x,y,s,FG);
        text(x+8,y,used?"YES":"NO",used?GREEN:DIM);
        if(used) {
            text(x+18,y,sell?"SELL":"BUY",sell?ORANGE:BLUE);
            money(s,cached[30]+bits(32,13)*cached[31]);text(x+26,y,s,FG);
            decimal(s,bits(0,32));text(x+40,y,s,FG);
        } else text(x+18,y,"(free)",DIM);
    }
    text(x,33,"WHAT AM I LOOKING AT?",PURPLE);
    text(x,35,"Every order gets a numbered slot in the FPGA's memory. When an order",FG);
    text(x,36,"leaves the book its slot becomes free and is reused.",FG);
}
static void orders_page(void) {
    header("MY ORDERS","Up/Down = scroll the list   PgUp/PgDn = next screen");
    text(2,2,"ORDER ID           SIDE  PRICE ($)   SHARES  PRICE STEP  MEMORY SLOT",DIM);
    int skip=(int)cached[14],seen=0,row=0;
    for(int set=0;set<1024 && row<36;set++) {
        query(2,set,19);
        // Query each slot after extracting the hash way from this snapshot.
        for(int way=0;way<8 && row<36;way++) if(bits(way*76+75,1)) {
            if(seen++<skip) continue;
            uint32_t idlo=bits(way*76,32),idhi=bits(way*76+32,32);
            int slot=bits(way*76+64,11);
            query(1,slot,2);
            char s[24],id[17];int y=4+row++;
            hex64(id,idlo,idhi);
            text(2,y,id,FG);
            text(22,y,bits(45,1)?"SELL":"BUY",bits(45,1)?ORANGE:BLUE);
            money(s,cached[30]+bits(32,13)*cached[31]);text(28,y,s,FG);
            decimal(s,bits(0,32));text(40,y,s,FG);
            decimal(s,bits(32,13));text(50,y,s,DIM);
            decimal(s,slot);text(62,y,s,DIM);
            query(2,set,19);
        }
    }
    for(int index=0;index<8 && row<36;index++) {
        query(3,index,3);
        if(!bits(75,1)) continue;
        if(seen++<skip) continue;
        uint32_t idlo=bits(0,32),idhi=bits(32,32);
        int slot=bits(64,11);
        query(1,slot,2);
        char s[24],id[17];int y=4+row++;
        hex64(id,idlo,idhi);text(2,y,id,FG);
        text(22,y,bits(45,1)?"SELL":"BUY",bits(45,1)?ORANGE:BLUE);
        money(s,cached[30]+bits(32,13)*cached[31]);text(28,y,s,FG);
        decimal(s,bits(0,32));text(40,y,s,FG);
        decimal(s,bits(32,13));text(50,y,s,DIM);
        decimal(s,slot);text(62,y,s,DIM);
    }
        explain(84,4,"WHAT AM I LOOKING AT?","Every order that is waiting in the book right now.","BUY orders (BID) are blue, SELL orders (ASK) are orange.","<-- PRICE and SHARES: what the person wants.","<-- Other columns show where the FPGA stores it.");
    text(2,42,"Read live from the FPGA's memory, including new orders.",DIM);
}
int main(void) {
    for(;;) {
        for(int i=0;i<64;i++) cached[i]=UI[i];
        record_history();
        bank=FRONT_BANK?0:1;
        clear_screen();
        switch(cached[0]&15) {
            case 0:market();break;
            case 1:orders_page();break;
            case 2:hash_page();break;
            case 3:events_page();break;
            case 5:levels_page();break;
            case 6:slots_page();break;
            default:history();break;
        }
        PRESENT=(uint32_t)bank|(((cached[0]&15)==0)?2u:0u);
        while((int)FRONT_BANK!=bank) { }
    }
}
