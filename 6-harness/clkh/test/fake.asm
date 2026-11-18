\ fake.asm: a stand-in for disc Elite, for testing the harness (clkh's serve
\ mode, elib.mjs, and bcompare's mixed run: this disc's reference on jsbeeb's
\ Model B, its candidate on clkh's Electron). It runs on both machines (the
\ MOS tells it which, for the paging) and has the labels the harness hooks:
\ S%, TT170, QU5, the title loop's TLL2 calling RDKEY, BAY, then a flight
\ loop TT100, M%, DOKEY (keys read one by one through DKS4, whose DKS4+17 is
\ DKSX, where the harness puts a key's state in X), MLOOP; the interrupt's
\ DEC LASCT (LASDEC, on IRQ1V); RDKEY, Rd2 and DKS4 in sideways RAM (slot 4,
\ "H"), reached through far calls whose frames hold farret. The game state
\ is at the original's addresses (the pilot's variables, the ship slots K%):
\ ships move by the keys and RAND, the laser kills one in the sights, and
\ every 64th iteration OSFILE 5 makes the filing system write its catalogue
\ over WP and its scratch bytes into zero page.
\ make: python3 6-harness/clkh/test/fake.py (BAD = 1: a variant whose laser
\ pulse is one longer, the control that must differ: fake-bad.ssd)

\ the original's addresses (4-reference-binaries/sth/flight-symbols.txt)
RAND = &00 : ECMA = &30 : QQ22 = &2E : MSTG = &45 : INWK = &46 : DELTA = &7D
Q = &81 : R = &82 : MCNT = &8A : DL = &8B : TYPE = &8C : QQ11 = &87 : QQ12 = &8E
K4 = &E0
UP = &300 : FRIN = &311 : MANY = &31E : SSPR = &320 : JUNK = &33E : auto = &33F
MSAR = &344 : VIEW = &345 : LASCT = &346 : JSTX = &34C : JSTY = &34D
QQ0 = &359 : QQ1 = &35A : CASH = &361 : QQ14 = &365 : GCNT = &367 : LASER = &368
ECM = &380 : BOMB = &382 : ENGY = &383 : DKCMP = &384 : GHYP = &385 : ESCP = &386
NOMSL = &38B : FSH = &3A5 : ASH = &3A6 : ENERGY = &3A7 : QQ29 = &3AD : SLSP = &3B0
QQ8 = &3BF : QQ9 = &3C1 : QQ10 = &3C2 : DNOIZ = &3C6 : CATF = &3CF
Kpc = &900 : WP = &E00 : LSO = &E00 : CPIR = &FD2
NI = 37

\ the program's own zero page (in the compared zero page, below K4)
dkk = &60 : ptr = &62 : t0 = &64 : t1 = &65 : t2 = &66 : kf = &67 : slot = &68
tmpa = &69 : fvec = &6A : rnd2 = &6C : wpseen = &6E : kills = &6F

OSFILE = &FFDD : OSBYTE = &FFF4 : OSWRCH = &FFEE
IRQ1V = &204

ORG &2000
.start
    \ (about three seconds before S%, as the original's loader takes longer:
    \ blib.mjs's boot runs a second past the BREAK before its hooks)
    LDA #24 : STA t0
.W1 LDX #0 : LDY #0
.W2 DEX : BNE W2 : DEY : BNE W2 : DEC t0 : BNE W1
    \ the cursor off (the game takes the VDU's workspace, UP; the MOS's
    \ bytes there are the boot's leftovers, seeded by the harness)
    LDX #0
.S3 LDA vdu,X : JSR OSWRCH : INX : CPX #10 : BNE S3
.Spc
    JMP S1
.S1
    SEI
    LDA IRQ1V : STA oldirq : LDA IRQ1V+1 : STA oldirq+1
    LDA #LO(LASIRQ) : STA IRQ1V : LDA #HI(LASIRQ) : STA IRQ1V+1
    CLI
    \ which machine: OSBYTE 0 with X = 1 gives 0 on the Electron's MOS 1.00
    LDA #0 : LDX #1 : JSR OSBYTE
    LDA #0 : CPX #0 : BNE S2 : LDA #&FF
.S2
    STA elkm
    \ the bank: slot 4, its number in BANKH, its code copied in
    LDA #4 : STA BANKH
    LDA &F4 : PHA
    LDA BANKH : STA &F4 : JSR page
    LDX #0
.S4 LDA bankimg,X : STA &8000,X : LDA bankimg+256,X : STA &8100,X : INX : BNE S4
    PLA : STA &F4 : JSR page
    \ the game's variables (but zero page from &90, WP and NA%, which are
    \ left as the boot left them: the harness seeds them)
    LDA #0 : LDX #0
.S5 STA &00,X : INX : CPX #&90 : BNE S5
    LDX #0
.S6 STA UP,X : INX : CPX #CATF+1-UP : BNE S6
    LDX #0
.S7 STA Kpc,X : STA Kpc+&100,X : STA Kpc+&200,X : STA Kpc+&300,X : INX : BNE S7
    \ (the serve mode's test of registers and memory set at a stop: C before
    \ an LDY #, memory before a JSR; serve-test.mjs)
.STC
    LDY #0 : LDA #0 : ADC #0 : STA stc
.STJ
    JSR stsub
.TT170
    LDA #1 : STA QQ12
    LDA #&42 : STA RAND : LDA #&17 : STA RAND+1 : LDA #&C3 : STA RAND+2 : LDA #&5A : STA RAND+3
.QU5
    NOP
.TLL2
    JSR FRDKEY
    CPX #&62 : BNE TLL2
.BAY
    LDA #0 : STA QQ12 : STA QQ11
    LDA #128 : STA JSTX : STA JSTY
    LDA #12 : STA DELTA
    LDX #1
.B1 STX slot : JSR spawn : LDX slot : INX : CPX #4 : BNE B1
    LDA #&FF : STA MCNT : STA ENERGY : STA FSH : STA ASH
    JMP TT100

.stsub LDA stv : STA stj : RTS
.stc EQUB &EE
.stv EQUB 0
.stj EQUB &EE
.vdu EQUB 23, 1, 0, 0, 0, 0, 0, 0, 0, 0
.oldirq EQUW 0

\ the interrupt: LASCT counted down at every interrupt (the harness undoes it)
.LASIRQ
    LDA LASCT : BEQ L1
.LASDEC
    DEC LASCT
.L1 JMP (oldirq)

\ paging: ROMSEL on the Model B, &FE05 on the Electron (from 8-11, a write
\ of 12 first); A is the slot
.page
    BIT elkm : BMI pg1
    STA &FE30 : RTS
.pg1
    PHA : PHP : SEI : LDA #12 : STA &FE05 : PLP : PLA
    STA &FE05 : RTS

\ far calls into the bank: the frame holds farret's return, the caller's
\ slot, then the caller's return (blib.mjs: callerAt)
.FRDKEY
    LDA #LO(RDKEY) : STA fvec : LDA #HI(RDKEY) : STA fvec+1 : JMP farcall
.FDKS4
    STX tmpa : LDA #LO(DKS4) : STA fvec : LDA #HI(DKS4) : STA fvec+1 : LDX tmpa
.farcall
    LDA &F4 : PHA
    LDA BANKH : STA &F4 : JSR page
    LDA fvec : JSR jvec
.farret
    STA tmpa : PLA : STA &F4 : JSR page : LDA tmpa : RTS
.jvec
    JMP (fvec)

\ the flight loop
.TT100
    NOP
.Mpc
    DEC MCNT
    JSR DOKEY
    JSR fly
    LDA MCNT : AND #63 : BNE M1
    JSR catalogue
.M1
    \ (a stardust-like read of WP: the catalogue's bytes there are the
    \ filing system's, set to 0 by the harness before they are read)
    LDA WP+&40 : EOR wpseen : STA wpseen
    \ a pause whose length depends on the state (the two machines' speeds differ)
    LDY JSTX
.M2 LDX #20
.M3 DEX : BNE M3 : DEY : BNE M2
.MLOOP
    JMP TT100

\ OSFILE 5 (read a file's attributes): the filing system reads the
\ catalogue into &0E00-&0FFF
.catalogue
    LDA #LO(fname) : STA fblk : LDA #HI(fname) : STA fblk+1
    LDX #LO(fblk) : LDY #HI(fblk) : LDA #5 : JSR OSFILE
    RTS
.fname EQUS "PROG", 13
.fblk SKIP 18

\ DOKEY: each key's state through DKS4, its effects at once
.keys EQUB &67, &66, &42, &51, &62, &68, &41, &22, &23, &65   \ > < X S SPACE / A E T M
.DOKEY
    LDY #0
.D1 STY t2
    LDX keys,Y : JSR FDKS4
    LDY t2
    ASL A : ROL kf
    INY : CPY #10 : BNE D1
    \ kf: bit 9-0 order lost to 8 bits: the last 8 keys (X S SPACE / A E T M)
    \ > and < again, for the roll
    LDX #&67 : JSR FDKS4 : BPL D2 : LDA JSTX : SEC : SBC #8 : BCC D2 : STA JSTX
.D2 LDX #&66 : JSR FDKS4 : BPL D3 : LDA JSTX : CLC : ADC #8 : BCS D3 : STA JSTX
.D3 LDA kf : AND #&80 : BEQ D4 : LDA JSTY : SEC : SBC #8 : BCC D4 : STA JSTY   \ X
.D4 LDA kf : AND #&40 : BEQ D5 : LDA JSTY : CLC : ADC #8 : BCS D5 : STA JSTY   \ S
.D5 LDA kf : AND #&20 : BEQ D6 : LDA DELTA : CMP #40 : BCS D6 : INC DELTA     \ SPACE
.D6 LDA kf : AND #&10 : BEQ D7 : LDA DELTA : BEQ D7 : DEC DELTA               \ /
.D7 LDA kf : AND #&08 : BEQ D8 : LDA #8+BAD : STA LASCT : JSR fire            \ A (BAD: a control that must differ)
.D8 LDA kf : AND #&01 : BEQ D9 : LDA NOMSL : BEQ D9 : DEC NOMSL               \ M
.D9 RTS

\ DORND
.dornd
    LDA RAND : ROL A : TAX : ADC RAND+2 : STA RAND : STX RAND+2
    LDA RAND+1 : TAX : ADC RAND+3 : STA RAND+1 : STX RAND+3
    RTS

\ ptr = the slot X's block
.blk
    LDA #0 : STA ptr+1 : TXA : STA ptr
    LDY #5
.bk1 CLC : LDA ptr : ADC ptr : STA ptr : ROL ptr+1 : DEY : BNE bk1   \ X * 32
    TXA : ASL A : ASL A : CLC : ADC ptr : STA ptr : BCC bk2 : INC ptr+1   \ + X * 4
.bk2 TXA : CLC : ADC ptr : STA ptr : BCC bk3 : INC ptr+1             \ + X = X * 37
.bk3 CLC : LDA ptr : ADC #LO(Kpc) : STA ptr : LDA ptr+1 : ADC #HI(Kpc) : STA ptr+1
    RTS

\ a ship in slot X: a Krait (hostile), ahead at a random place
.spawn
    LDA #19 : STA FRIN,X
    JSR blk
    LDY #NI-1 : LDA #0
.sp1 STA (ptr),Y : DEY : BPL sp1
    JSR dornd : LDY #0 : STA (ptr),Y : AND #3 : INY : STA (ptr),Y
    JSR dornd : AND #&80 : LDY #2 : STA (ptr),Y
    JSR dornd : LDY #3 : STA (ptr),Y : AND #1 : INY : STA (ptr),Y
    JSR dornd : AND #&80 : LDY #5 : STA (ptr),Y
    JSR dornd : LDY #6 : STA (ptr),Y : AND #7 : ORA #8 : INY : STA (ptr),Y
    LDA #4 : LDY #36 : STA (ptr),Y
    RTS

\ t0 t1 t2 = the coordinate at (ptr),Y as a 24-bit two's complement number
.getc
    LDA (ptr),Y : STA t0 : INY : LDA (ptr),Y : STA t1 : INY : LDA (ptr),Y : DEY : DEY
    STA t2 : AND #&7F : STA tmpa
    LDA t2 : BPL gc1
    SEC : LDA #0 : SBC t0 : STA t0 : LDA #0 : SBC t1 : STA t1 : LDA #0 : SBC tmpa : STA t2 : RTS
.gc1 RTS
.putc
    LDA t2 : BPL pc1
    SEC : LDA #0 : SBC t0 : STA t0 : LDA #0 : SBC t1 : STA t1 : LDA #0 : SBC t2 : ORA #&80 : STA t2
.pc1 LDA t0 : STA (ptr),Y : INY : LDA t1 : STA (ptr),Y : INY : LDA t2 : STA (ptr),Y : DEY : DEY
    RTS

\ the ships move: x by the roll, y by the pitch, z by our speed
.fly
    LDX #1
.f1 STX slot
    LDA FRIN,X : BNE f2 : JMP f9
.f2 JSR blk
    \ exploding: replaced by a new one
    LDY #31 : LDA (ptr),Y : AND #&20 : BEQ f3 : LDX slot : JSR spawn : JMP f9
.f3 LDA JSTX : SEC : SBC #128 : CMP #&80 : ROR A : CMP #&80 : ROR A : STA rnd2   \ (128 - JSTX) / 4, signed, negated
    LDY #0 : JSR getc : LDA rnd2 : JSR add8 : JSR dornd : AND #3 : SEC : SBC #1 : JSR add8 : LDY #0 : JSR putc
    LDA JSTY : SEC : SBC #128 : CMP #&80 : ROR A : CMP #&80 : ROR A : STA rnd2
    LDY #3 : JSR getc : LDA rnd2 : JSR add8 : LDY #3 : JSR putc
    LDY #6 : JSR getc : LDA DELTA : LSR A : EOR #&FF : JSR add8 : LDY #6 : JSR putc
    \ too close or behind: a new one
    LDA t2 : BMI f8 : LDA t1 : CMP #1 : BCS f9
.f8 LDX slot : JSR spawn
.f9 LDX slot : INX : CPX #4 : BEQ f10 : JMP f1
.f10 RTS
\ t0 t1 t2 += A (sign-extended)
.add8
    STA tmpa : CLC : ADC t0 : STA t0
    LDA tmpa : AND #&80 : BEQ a81 : LDA #&FF
.a81 STA rnd2+1 : ADC t1 : STA t1 : LDA rnd2+1 : ADC t2 : STA t2
    RTS

\ the laser: the first ship whose x and y high bytes are 0 and z is ahead is killed
.fire
    LDX #1
.fi1 STX slot : JSR blk
    LDY #1 : LDA (ptr),Y : BNE fi2 : LDY #4 : LDA (ptr),Y : BNE fi2
    LDY #8 : LDA (ptr),Y : BMI fi2
    LDY #31 : LDA (ptr),Y : ORA #&20 : STA (ptr),Y : INC kills : RTS
.fi2 LDX slot : INX : CPX #4 : BNE fi1
    RTS

.BANKH EQUB 4
.elkm EQUB 0
ALIGN &100
.NApc
    EQUS "JAMESON", 13
    SKIP 70
.CHK EQUB &55
.progend

\ the bank's code, assembled at &8000, carried in the program after it
ORG &8000
.bankstart
.RDKEY
    LDA #0
.Rd2
    EOR #&80 : TAX : RTS
\ DKS4: X the key's number; at DKS4+17 (DKSX) X holds it with bit 7 set
\ if the key is down (the harness puts it there); returns A = X, N set if down
.DKS4
    STX dkk
    NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP
    LDX dkk
.DKSX
    LDA #&0B
    TXA : RTS
.bankend

bankimg = progend
COPYBLOCK bankstart, bankend, bankimg
progtop = (bankimg + bankend - bankstart + 255) AND &FF00
SAVE "PROG", start, progtop, start
