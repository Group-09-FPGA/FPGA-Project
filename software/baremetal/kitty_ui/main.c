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
#define BG 8
#define SELECTED 7

static uint32_t words[19];
static uint32_t cached[64];
static uint16_t bids[128], asks[128];
static uint32_t bid_values[128], ask_values[128];
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
    highlight(2,0," FPGA ORDER BOOK ");
    text(22,0,"/",DIM);text(25,0,page,PURPLE);
    text(130,0,"FPGA LIVE",GREEN);
    stripe(43,9);
    if((cached[0]&15)==7 && ((cached[0]>>4)&7)>=2 && ((cached[0]>>4)&7)<=5)
        text(2,43,"NUMERIC EDIT: digits type into field   F1-F8 pages   Tab after valid value",FG);
    else
        text(2,43,"1 Market   2 Orders   3 Hash   4 Events   5 Status   6 Levels   7 Slots   8 Order Entry",FG);
    text(2,44,help,DIM);
}
static void plot_point(int chart,int x,int y,int last_y,int color) {
    if(x<0 || x>=512 || y<0 || y>=256) return;
    int lo=y<last_y?y:last_y,hi=y>last_y?y:last_y;
    uint32_t word=(uint32_t)y | ((uint32_t)lo<<9) | ((uint32_t)hi<<18) | ((uint32_t)color<<27);
    PLOT[bank*1024+chart*512+x]=word;
}
static void draw_graph(int chart,const uint32_t *values,int count) {
    for(int x=0;x<512;x++) PLOT[bank*1024+chart*512+x]=0x1fffffff;
    uint32_t low=0xffffffffu,high=0;
    for(int i=0;i<count;i++) if(values[i]) {
        if(values[i]<low) low=values[i];
        if(values[i]>high) high=values[i];
    }
    if(low==0xffffffffu) return;
    if(high==low) {high+=1000;low=low>1000?low-1000:0;}
    else {uint32_t pad=(high-low)/8+1;high+=pad;low=low>pad?low-pad:0;}
    int previous=-1,previous_y=0;uint32_t previous_value=0;
    for(int i=0;i<count;i++) if(values[i]) {
        int x=count==1?511:i*511/(count-1);
        int y=255-(int)(((uint64_t)(values[i]-low)*255)/(high-low));
        int color=previous<0?0:values[i]>previous_value?1:values[i]<previous_value?2:0;
        if(previous>=0) {
            for(int k=previous+1;k<x;k++) plot_point(chart,k,previous_y,previous_y,color);
            plot_point(chart,x,y,previous_y,color);
        } else plot_point(chart,x,y,y,0);
        previous=x;previous_y=y;previous_value=values[i];
    }
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
        bids[i]=(uint16_t)bits(32,12);
        asks[i]=(uint16_t)bits(0,16);
    }
}
static void market(void) {
    header("MARKET","F1-F8 pages   H history   Tab focus   Up/Down browse samples   PgUp/PgDn older/newer");
    char s[24];
    text(2,2,"BEST BID",DIM);text(51,2,"BEST ASK",DIM);text(100,2,"SPREAD",DIM);
    if(cached[15]&2) {money(s,cached[16]);text(2,3,s,GREEN);} else text(2,3,"--",DIM);
    if(cached[15]&4) {money(s,cached[18]);text(51,3,s,RED);} else text(51,3,"--",DIM);
    if((cached[15]&6)==6 && cached[18]>=cached[16]) {
        money(s,cached[18]-cached[16]);text(100,3,s,FG);
    } else text(100,3,"--",DIM);
    int focus=(cached[0]>>4)&7;
    text(2,4,"BID HISTORY  /  GREEN RISE   RED FALL   GREY FLAT",focus==0?GOLD:GREEN);
    text(2,23,"ASK HISTORY  /  GREEN RISE   RED FALL   GREY FLAT",focus==1?GOLD:RED);
    load_quotes();draw_graph(0,bid_values,quote_n);draw_graph(1,ask_values,quote_n);
    text(80,6,"LIVE BOOK",PURPLE);
    label_u(80,8,"Active orders",cached[20],FG);
    label_u(80,9,"Completed events",cached[21],FG);
    text(80,11,"NETWORK PIPELINE",PURPLE);
    label_u(80,13,"RX frames",cached[22],FG);
    label_u(80,14,"UDP packets",cached[26],FG);
    label_u(80,15,"Mold messages",cached[24],FG);
    label_u(80,16,"ITCH events",cached[27],FG);
    label_u(80,17,"FIFO events",cached[28],FG);
    label_u(80,19,"CRC errors",cached[23],cached[23]?RED:FG);
    label_u(80,20,"Sequence gaps",cached[25],cached[25]?RED:FG);
    text(80,22,"STORAGE",PURPLE);
    text(80,24,"Quotes, graphs and rows are from FPGA memory.",DIM);
    text(80,26,"[H] Quote history",focus==2?GOLD:FG);
    label_u(80,27,"History offset",cached[14],FG);
    if(!(cached[15]&1)) text(80,28,"BOOK INVALID",RED);
}
static void history(void) {
    header("QUOTE HISTORY","F1-F8 or 1-8 leave   Up/Down scroll   PgUp/PgDn one screen");
    text(2,2,"EVENT                 BEST BID               BEST ASK",DIM);
    uint32_t meta=cached[32];int count=(int)(meta&255),next=(int)((meta>>8)&127);
    int offset=(int)cached[14];
    for(int row=0;row<38 && row+offset<count;row++) {
        query(7,(next-1-offset-row)&127,6);
        char s[24];int y=row+4;
        decimal(s,bits(0,32));text(2,y,s,FG);
        if(bits(173,1)) {money(s,bits(141,32));text(24,y,s,GREEN);}
        if(bits(108,1)) {money(s,bits(76,32));text(48,y,s,RED);}
    }
    text(96,4,"[H] Stay on history",DIM);
    text(96,5,"[1-8] Leave history",DIM);
}
static void status_page(void) {
    header("STATUS","F1-F8 or 1-8 select a page   H quote history");
    text(2,2,"FPGA BOOK",PURPLE);
    text(2,4,(cached[15]&1)?"VALID":"INVALID",(cached[15]&1)?GREEN:RED);
    label_hex(2,5,"Error code",cached[29]);
    label_u(2,6,"Active orders",cached[20],FG);
    label_u(2,7,"Completed events",cached[21],FG);
    text(2,10,"PIPELINE COUNTERS",PURPLE);
    label_u(2,12,"RX frames",cached[22],FG);
    label_u(2,13,"UDP packets",cached[26],FG);
    label_u(2,14,"Mold messages",cached[24],FG);
    label_u(2,15,"ITCH events",cached[27],FG);
    label_u(2,16,"FIFO events",cached[28],FG);
    label_u(2,17,"CRC errors",cached[23],cached[23]?RED:FG);
    label_u(2,18,"Sequence gaps",cached[25],cached[25]?RED:FG);
    text(2,21,"PRICE CONFIGURATION",PURPLE);
    char s[24];money(s,cached[30]);text(2,23,"Base",DIM);text(24,23,s,FG);
    money(s,cached[31]);text(2,24,"Tick",DIM);text(24,24,s,FG);
    text(2,28,"Keyboard orders enter after Ethernet parsing; pipeline counters remain network-only.",DIM);
}
static void order_entry(void) {
    header("ORDER ENTRY","F1-F8 pages   Tab focus   Arrows edit/browse   Enter submit   Esc restore edit");
    uint32_t flags=cached[0];int focus=(flags>>4)&7,action=(flags>>7)&7;
    const char *actions[7]={"A Add","F Add attributed","E Execute","C Execute priced",
        "X Cancel","D Delete","U Replace"};
    text(2,2,"KEYBOARD SUBMISSION: ENABLED",GREEN);
    text(2,4,"ACTION",DIM);text(28,4,actions[action<7?action:0],focus==0?GOLD:FG);
    text(2,6,"SIDE",DIM);text(28,6,(flags&(1u<<10))?"SELL":"BUY",focus==1?GOLD:FG);
    if(action>=2) text(40,6,"inherited from selected order",DIM);
    const char *labels[4]={"PRICE","QUANTITY","ORDER ID","NEW ID"};
    for(int f=0;f<4;f++) {
        int y=8+f*3;int len=(cached[1]>>(f*5))&31;
        int cursor=(cached[2]>>(f*5))&31;
        text(2,y,labels[f],DIM);
        for(int c=0;c<len && c<16;c++) {
            uint32_t word=cached[33+f*4+c/4];
            char ch=(char)(word>>((3-c%4)*8));
            cell(28+c,y,ch,focus==f+2?GOLD:FG,BG);
        }
        if(focus==f+2) cell(28+cursor,y+1,'^',GOLD,BG);
    }
    text(2,21,"ACTIVE ORDER",PURPLE);
    if(flags&(1u<<13)) {
        char id[17];hex64(id,cached[9],cached[10]);text(2,23,id,FG);
        text(2,24,"Loaded from FPGA hash and slot RAM",DIM);
    } else text(2,23,"No active order selected",DIM);
    if(flags&(1u<<14)) text(2,25,"Scanning FPGA order storage...",GOLD);
    text(2,28,"Tab/Shift+Tab focus   Left/Right action, side, cursor   Up/Down orders",DIM);
    text(2,29,"Enter submits once   Escape restores field   Backspace/Delete edit",DIM);
    text(2,31,"Price: four decimal places   IDs: 1-16 hexadecimal digits",DIM);
    text(2,33,"RESULT",PURPLE);
    int result=(flags>>15)&31;
    const char *messages[12]={"Ready","Queued","Sent to core","Invalid field","Queue busy",
        "Invalid price or tick","Invalid quantity","Invalid order ID","Order changed: reselect",
        "Disabled","Book invalid","Quantity exceeds stored order"};
    text(2,35,messages[result<12?result:0],result>2?RED:GREEN);
    if(!(flags&(1u<<12))) text(2,37,"Focused field needs repair before Tab or submission",RED);
    label_u(2,39,"Local completed",cached[50],FG);
    if(cached[50]) {
        text(2,40,(cached[51]&256)?"Last local order accepted by book":"Last local order rejected by book",
             (cached[51]&256)?GREEN:RED);
        if(!(cached[51]&256)) label_hex(65,40,"Error",cached[51]&255);
    }
    text(84,4,"LOCAL ORDER PATH",PURPLE);
    text(84,6,"Keyboard -> local FIFO -> arbiter -> LOB",DIM);
    text(84,8,"Ethernet orders can arrive in the same session.",DIM);
}
static void hash_page(void) {
    header("HASH","F1-F8 or 1-8 pages   Tab set/way   Up/Down set   Left/Right way   PgUp/PgDn screen");
    int set=cached[11]&1023;
    char s[24];text(2,2,"SET",((cached[0]>>4)&7)==0?GOLD:DIM);
    decimal(s,set);text(8,2,s,GOLD);
    text(2,4,"WAY  VALID  SLOT   ORDER REFERENCE",((cached[0]>>4)&7)==1?GOLD:DIM);
    query(2,set,19);
    for(int way=0;way<8;way++) {
        int bit=way*76,y=6+way*2;
        decimal(s,way);text(2,y,s,FG);
        text(8,y,bits(bit+75,1)?"YES":"NO",bits(bit+75,1)?GREEN:DIM);
        decimal(s,bits(bit+64,11));text(16,y,s,FG);
        char id[17];hex64(id,bits(bit,32),bits(bit+32,32));text(24,y,id,FG);
    }
    text(2,24,"COLLISION STASH",PURPLE);
    for(int index=0;index<8;index++) {
        query(3,index,3);
        if(bits(75,1)) {
            char id[17];hex64(id,bits(0,32),bits(32,32));
            decimal(s,index);text(2,26+index,s,FG);
            text(8,26+index,id,FG);
        }
    }
    text(2,36,"Hash ways and stash are read from live FPGA RAM.",DIM);
    text(2,38,"Up/Down set  Left/Right way  PgUp/PgDn screen",DIM);
}
static void events_page(void) {
    header("EVENTS","F1-F8 or 1-8 pages   Up/Down scroll   PgUp/PgDn one screen");
    text(2,2,"COMPLETED  TYPE  ORDER ID          STORAGE TRACE",DIM);
    uint32_t meta=cached[32];int count=(int)((meta>>15)&511),next=(int)((meta>>24)&255);
    int offset=(int)cached[14];
    for(int row=0;row<38 && row+offset<count;row++) {
        query(8,(next-1-offset-row)&255,13);
        char s[24],id[17];int y=row+4;
        decimal(s,bits(362,32));text(2,y,s,FG);
        int op=bits(311,4);decimal(s,op);text(14,y,s,GOLD);
        hex64(id,bits(247,32),bits(279,32));text(22,y,id,FG);
        hex32(s,bits(0,32),8);text(48,y,s,DIM);
    }
    text(2,42,"Records are committed FPGA journal entries; no replay or fixtures.",DIM);
}
static void levels_page(void) {
    header("LEVELS","F1-F8 or 1-8 pages   Up/Down rows   PgUp/PgDn one screen");
    int center=cached[13]&8191;
    text(2,2,"INDEX       BID QTY     BID ORDERS     ASK QTY     ASK ORDERS",DIM);
    for(int row=0;row<36;row++) {
        int index=center+row;if(index>=8192) break;
        char s[12];int y=row+4;
        decimal(s,index);text(2,y,s,FG);
        query(4,index,1);decimal(s,words[0]);text(14,y,s,GREEN);
        query(6,index,1);decimal(s,words[0]&4095);text(28,y,s,GREEN);
        query(4,8192+index,1);decimal(s,words[0]);text(43,y,s,RED);
        query(6,8192+index,1);decimal(s,words[0]&4095);text(57,y,s,RED);
    }
    text(90,4,"All level values come from FPGA price RAM.",DIM);
}
static void slots_page(void) {
    header("SLOTS","F1-F8 or 1-8 pages   Up/Down rows   PgUp/PgDn one screen");
    int center=cached[12]&2047;
    text(2,2,"SLOT  VALID  SIDE  PRICE INDEX  REMAINING SHARES",DIM);
    for(int row=0;row<36;row++) {
        int index=center+row;if(index>=2048) break;
        query(1,index,2);
        char s[12];int y=row+4;
        decimal(s,index);text(2,y,s,FG);
        text(8,y,bits(46,1)?"YES":"NO",bits(46,1)?GREEN:DIM);
        text(15,y,bits(45,1)?"ASK":"BID",bits(45,1)?RED:GREEN);
        decimal(s,bits(32,13));text(22,y,s,FG);
        decimal(s,bits(0,32));text(36,y,s,FG);
    }
    text(80,4,"Rows are live FPGA slot RAM.",DIM);
}
static void orders_page(void) {
    header("ORDERS","F1-F8 or 1-8 pages   Up/Down browse   Enter open Order Entry   PgUp/PgDn screen");
    text(2,2,"REFERENCE          SIDE  PRICE INDEX  SHARES  SLOT  HASH SET",DIM);
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
            text(2,y,id,(idlo==cached[9] && idhi==cached[10] && (cached[0]&(1u<<13)))?GOLD:FG);
            text(22,y,bits(45,1)?"ASK":"BID",bits(45,1)?RED:GREEN);
            decimal(s,bits(32,13));text(30,y,s,FG);
            decimal(s,bits(0,32));text(45,y,s,FG);
            decimal(s,slot);text(58,y,s,FG);
            decimal(s,set);text(68,y,s,DIM);
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
        text(22,y,bits(45,1)?"ASK":"BID",bits(45,1)?RED:GREEN);
        decimal(s,bits(32,13));text(30,y,s,FG);
        decimal(s,bits(0,32));text(45,y,s,FG);
        decimal(s,slot);text(58,y,s,FG);
        text(68,y,"STASH",GOLD);
    }
    text(2,42,"Orders are scanned from FPGA hash and slot RAM, including live updates.",DIM);
}
int main(void) {
    for(;;) {
        for(int i=0;i<64;i++) cached[i]=UI[i];
        bank=FRONT_BANK?0:1;
        clear_screen();
        switch(cached[0]&15) {
            case 0:market();break;
            case 1:orders_page();break;
            case 2:hash_page();break;
            case 3:events_page();break;
            case 4:status_page();break;
            case 5:levels_page();break;
            case 6:slots_page();break;
            case 7:order_entry();break;
            default:history();break;
        }
        PRESENT=(uint32_t)bank|(((cached[0]&15)==0)?2u:0u);
        while((int)FRONT_BANK!=bank) { }
    }
}
