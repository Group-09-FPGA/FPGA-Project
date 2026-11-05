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
    if(p==7 && ((cached[0]>>4)&7)>=2 && ((cached[0]>>4)&7)<=5)
        text(2,43,"TYPING A NUMBER: digits go into the field   Tab = next field once the value is valid",FG);
    else {
        static const char *const names[7]={"1 Market","2 My Orders","3 Hash Table","4 Event Log",
            "5 Price Levels","6 Order Slots","7 Place Order"};
        static const int pages[7]={0,1,2,3,5,6,7};
        int x=2;
        for(int i=0;i<7;i++) {
            if(pages[i]==p) highlight(x,43,names[i]);else text(x,43,names[i],FG);
            for(const char *c=names[i];*c;c++) x++;
            x+=3;
        }
    }
    text(2,44,help,DIM);
}
static void plot_point(int chart,int x,int y,int last_y) {
    if(x<0 || x>=512 || y<0 || y>=256) return;
    int lo=y<last_y?y:last_y,hi=y>last_y?y:last_y;
    uint32_t word=(uint32_t)y | ((uint32_t)lo<<9) | ((uint32_t)hi<<18);
    PLOT[bank*1024+chart*512+x]=word;
}
static int y_of(uint32_t v) {
    return 255-(int)(((uint64_t)(v-scale_low)*255)/(scale_high-scale_low));
}
static void draw_line(int chart,const uint32_t *values,int count) {
    for(int x=0;x<512;x++) PLOT[bank*1024+chart*512+x]=0x1fffffff;
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
    for(int c=0;c<2;c++) for(int x=0;x<512;x++) PLOT[bank*1024+c*512+x]=0x1fffffff;
    if(low==0xffffffffu) return 0;
    if(high==low) {high+=1000;low=low>1000?low-1000:0;}
    else {uint32_t pad=(high-low)/8+1;high+=pad;low=low>pad?low-pad:0;}
    scale_low=low;scale_high=high;
    draw_line(0,bid_values,count);draw_line(1,ask_values,count);
    return 1;
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
    return row<6?6:row>37?37:row;
}
static void market(void) {
    header("MARKET","H = every past price   Up/Down or PgUp/PgDn = scroll back in time   7 = place your own order");
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
    if(!(cached[15]&1)) text(x,30,"BOOK INVALID: an order was rejected. Reset the board.",RED);
}
static void explain(int x,int y,const char *title,const char *a,const char *b,const char *c,const char *d) {
    text(x,y,title,PURPLE);
    if(a) text(x,y+2,a,FG);
    if(b) text(x,y+3,b,FG);
    if(c) text(x,y+4,c,DIM);
    if(d) text(x,y+5,d,DIM);
}
static void history(void) {
    header("PRICE HISTORY","Up/Down or PgUp/PgDn = scroll   1-7 = leave this page");
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
static void order_entry(void) {
    header("PLACE AN ORDER","Tab = next field   Left/Right = change choice   Enter = send   Esc = undo your edit");
    uint32_t flags=cached[0];int focus=(flags>>4)&7,action=(flags>>7)&7;
    if(action>6) action=0;
    int sell=(flags&(1u<<10))!=0,field_ok=(flags&(1u<<12))!=0;
    static const char *actions[7]={"A  Add a new order","F  Add (with trader tag)","E  Order was traded",
        "C  Order was traded at a price","X  Cancel some shares","D  Delete the whole order","U  Replace with a new order"};
    // Which of PRICE, QUANTITY, ORDER ID, NEW ID this action needs.
    static const uint8_t used[7]={0x7,0x7,0x6,0x6,0x6,0x4,0xF};
    text(2,2,"Type an order below and press Enter. It joins the same book as the network orders.",DIM);
    text(2,4,"WHAT TO DO",DIM);text(28,4,actions[action],focus==0?GOLD:FG);
    text(2,6,"BUY OR SELL",DIM);
    if(action<2) {text(28,6,sell?"SELL":"BUY",focus==1?GOLD:(sell?ORANGE:BLUE));}
    else text(28,6,"(taken from the order you pick)",DIM);
    if(focus==0) text(60,4,"<-- Left/Right to pick",GOLD);
    if(focus==1) text(40,6,"<-- Left/Right: buy or sell",GOLD);
    static const char *labels[4]={"PRICE ($)","QUANTITY (shares)","ORDER ID","NEW ORDER ID"};
    static const char *hints[4]={"<-- dollars, 4 decimals","<-- whole number above 0",
        "<-- 1-16 digits 0-9, A-F","<-- 1-16 digits 0-9, A-F"};
    for(int f=0;f<4;f++) {
        int y=8+f*3,len=(cached[1]>>(f*5))&31,cursor=(cached[2]>>(f*5))&31;
        int on=(used[action]>>f)&1,here=focus==f+2;
        text(2,y,labels[f],on?DIM:BG);
        if(!on) {text(28,y,"not needed for this action",DIM);continue;}
        for(int c=0;c<len && c<16;c++) {
            uint32_t word=cached[33+f*4+c/4];
            cell(28+c,y,(char)(word>>((3-c%4)*8)),here?(field_ok?GOLD:RED):FG,BG);
        }
        if(here) {
            cell(28+cursor,y+1,'^',GOLD,BG);
            text(46,y,hints[f],field_ok?GOLD:RED);
        }
    }
    text(2,21,"ORDER YOU PICKED",PURPLE);
    if(flags&(1u<<13)) {
        b_reset();b_str("Order ");b_id(cached[9],cached[10]);b_str(" is selected from the book.");
        text(2,23,buf,FG);
    } else if(action>=2) text(2,23,"Open 2 My Orders, pick one and press Enter, or use Up/Down here.",DIM);
    else text(2,23,"Not needed: an Add creates a brand new order.",DIM);
    if(flags&(1u<<14)) text(2,25,"Looking the order up...",GOLD);

    text(2,29,"RESULT",PURPLE);
    int result=(flags>>15)&31;
    static const char *messages[12]={"Ready - fill in the fields and press Enter.","Order queued...","Order sent to the book.",
        "That field is not valid yet.","Queue is busy, try again.","Price must be at or above the base price.",
        "Quantity must be a whole number above 0.","Order ID must be 1-16 hex digits.",
        "The book changed - pick the order again.","Keyboard orders are disabled.",
        "The book is invalid - reset the board.","Quantity is more than the order has left."};
    const char *m=messages[result<12?result:0];
    if(result==3) {
        if(focus==2) m="Price needs 4 decimals, e.g. 95.5000.";
        else if(focus==3) m="Quantity must be a whole number above 0.";
        else if(focus==4 || focus==5) m="ID may only use digits 0-9 and letters A-F.";
    }
    text(2,31,m,result>2?RED:GREEN);
    if(!field_ok) text(2,33,"The field with the red cursor must be fixed before Tab or Enter.",RED);
    if(cached[50]) {
        b_reset();b_str("Orders you sent so far: ");b_dec(cached[50]);text(2,36,buf,FG);
        text(2,37,(cached[51]&256)?"Last one: ACCEPTED by the book.":"Last one: REJECTED by the book.",
             (cached[51]&256)?GREEN:RED);
        if(!(cached[51]&256)) label_hex(2,38,"Error code",cached[51]&255);
    }

    int x=84;
    text(x,4,"WHAT YOU ARE ABOUT TO SEND",PURPLE);
    b_reset();
    switch(action) {
        case 0:case 1:
            b_str(sell?"SELL ":"BUY ");b_dec(cached[4]);b_str(" shares at ");b_money(cached[3]);break;
        case 2:b_str("A trade of ");b_dec(cached[4]);b_str(" shares of order ");b_id(cached[5],cached[6]);break;
        case 3:b_str("A trade of ");b_dec(cached[4]);b_str(" shares of order ");b_id(cached[5],cached[6]);break;
        case 4:b_str("Cancel ");b_dec(cached[4]);b_str(" shares of order ");b_id(cached[5],cached[6]);break;
        case 5:b_str("Remove order ");b_id(cached[5],cached[6]);b_str(" completely");break;
        default:b_str("Swap order ");b_id(cached[5],cached[6]);b_str(" for ");b_id(cached[7],cached[8]);break;
    }
    text(x,6,buf,field_ok?GREEN:DIM);
    if(action<2) {b_reset();b_str("as order ");b_id(cached[5],cached[6]);text(x,7,buf,DIM);}
    if(action==6) {b_reset();b_dec(cached[4]);b_str(" shares at ");b_money(cached[3]);text(x,7,buf,DIM);}
    text(x,9,"WHAT THIS MEANS",PURPLE);
    switch(action) {
        case 0:case 1:
            text(x,11,"A new order joins the book and waits for a match.",FG);
            text(x,12,"A BUY sets or raises the bid (blue line).",BLUE);
            text(x,13,"A SELL sets or lowers the ask (orange line).",ORANGE);break;
        case 2:case 3:
            text(x,11,"Shares of an existing order were bought or sold.",FG);
            text(x,12,"The order shrinks; it disappears when empty.",FG);break;
        case 4:
            text(x,11,"Takes some shares off an order without a trade.",FG);
            text(x,12,"The order stays, with fewer shares.",FG);break;
        case 5:
            text(x,11,"Removes the order from the book entirely.",FG);break;
        default:
            text(x,11,"Cancels the old order and adds a new one",FG);
            text(x,12,"with the new ID, quantity and price.",FG);break;
    }
    text(x,15,"ORDER JOURNEY",PURPLE);
    int stage=result==1?1:result==2?2:0;
    if(cached[50] && (cached[51]&256)) stage=3;
    text(x,17,"Keyboard",stage==0?GOLD:FG);text(x+9,17,"->",DIM);
    text(x+12,17,"Queue",stage==1?GOLD:FG);text(x+18,17,"->",DIM);
    text(x+21,17,"Order book",stage==2?GOLD:FG);text(x+32,17,"->",DIM);
    text(x+35,17,"Done",stage==3?GREEN:FG);
    text(x,19,"The order is checked, queued, then applied to the",DIM);
    text(x,20,"book by the FPGA. Check 1 Market for the result.",DIM);
}
static void hash_page(void) {
    header("HASH TABLE","Up/Down = next set   Left/Right = way   Tab = switch   PgUp/PgDn = jump");
    int set=cached[11]&1023;
    char s[24];text(2,2,"SET",((cached[0]>>4)&7)==0?GOLD:DIM);
    decimal(s,set);text(8,2,s,GOLD);
    text(2,4,"WAY  USED?  SLOT   ORDER ID",((cached[0]>>4)&7)==1?GOLD:DIM);
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
    explain(60,4,"UNDER THE HOOD: FINDING ORDERS FAST","The FPGA finds an order by its ID using a lookup table.","Each ID lands in one of 1024 sets, which hold 8 orders (ways).","<-- YES means a way holds an order. NO means it is free.","<-- The stash holds orders when a set is full.");
    text(2,36,"Read live from the FPGA's memory.",DIM);
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
static void levels_page(void) {
    header("PRICE LEVELS","Up/Down = rows   PgUp/PgDn = next screen");
    int center=cached[13]&8191;
    text(2,2,"STEP   PRICE ($)    BUY SHARES  BUY ORDERS   SELL SHARES  SELL ORDERS",DIM);
    for(int row=0;row<36;row++) {
        int index=center+row;if(index>=8192) break;
        char s[12];int y=row+4;
        decimal(s,index);text(2,y,s,DIM);
        money(s,cached[30]+(uint32_t)index*cached[31]);text(9,y,s,FG);
        query(4,index,1);decimal(s,words[0]);text(22,y,s,BLUE);
        query(6,index,1);decimal(s,words[0]&4095);text(34,y,s,BLUE);
        query(4,8192+index,1);decimal(s,words[0]);text(47,y,s,ORANGE);
        query(6,8192+index,1);decimal(s,words[0]&4095);text(60,y,s,ORANGE);
    }
    explain(80,4,"UNDER THE HOOD: PRICE LEVELS","The book keeps one row per possible price step.","Each row totals the shares waiting at that price.","<-- Blue: buyers at that price.","<-- Orange: sellers at that price.");
}
static void slots_page(void) {
    header("ORDER SLOTS","Up/Down = rows   PgUp/PgDn = next screen");
    int center=cached[12]&2047;
    text(2,2,"SLOT  IN USE?  SIDE  PRICE ($)    SHARES LEFT",DIM);
    for(int row=0;row<36;row++) {
        int index=center+row;if(index>=2048) break;
        query(1,index,2);
        char s[12];int y=row+4;
        decimal(s,index);text(2,y,s,FG);
        text(8,y,bits(46,1)?"YES":"NO",bits(46,1)?GREEN:DIM);
        text(16,y,bits(45,1)?"SELL":"BUY",bits(45,1)?ORANGE:BLUE);
        money(s,cached[30]+bits(32,13)*cached[31]);text(22,y,s,FG);
        decimal(s,bits(0,32));text(36,y,s,FG);
    }
    explain(70,4,"UNDER THE HOOD: ORDER SLOTS","The FPGA keeps up to 2048 orders in numbered slots.","YES = the slot holds a real order.","<-- Slots reused after an order leaves the book.","<-- Rows with NO are free space.");
}
static void orders_page(void) {
    header("MY ORDERS","Up/Down = browse   Enter = edit the selected order   PgUp/PgDn = next screen");
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
            text(2,y,id,(idlo==cached[9] && idhi==cached[10] && (cached[0]&(1u<<13)))?GOLD:FG);
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
    text(84,11,"Select a row with Up/Down, press Enter",DIM);
    text(84,12,"to change or cancel it in 7 Place Order.",DIM);
    text(2,42,"Read live from the FPGA's memory, including new orders.",DIM);
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
            case 5:levels_page();break;
            case 6:slots_page();break;
            case 7:order_entry();break;
            default:history();break;
        }
        PRESENT=(uint32_t)bank|(((cached[0]&15)==0)?2u:0u);
        while((int)FRONT_BANK!=bank) { }
    }
}
