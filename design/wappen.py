from PIL import Image, ImageDraw, ImageFont
import math, sys
FD="/tmp/claude-0/-home-claude/f5e48406-f58e-580c-88b6-8eadc376a9b1/scratchpad/fonts/"
BC=FD+"expo-google-fonts-barlow-condensed-0.2.3/package/BarlowCondensed_800ExtraBold.ttf"
S=2048; OUT=1024
G1=(12,60,37); G2=(28,106,66); GD=(18,80,50); CREAM=(247,243,231); GOLD=(222,174,46); GOLDD=(176,132,28)
STEEL=(196,203,208); STEELD=(128,138,146); INK=(26,36,30); WOOD=(232,204,150); BLACK=(30,32,30)
def font(sz): return ImageFont.truetype(BC,sz)
def grad(c1,c2):
    im=Image.new("RGB",(S,S)); d=ImageDraw.Draw(im)
    for y in range(S):
        t=y/S; d.line([(0,y),(S,y)],fill=tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3)))
    return im
def pencil(length=1900, w=140):
    im=Image.new("RGBA",(length,w+40),(0,0,0,0)); d=ImageDraw.Draw(im); o=20; tip=250
    d.rectangle((tip,o,length-170,o+w),fill=GOLD)
    d.rectangle((tip,o+w*0.36,length-170,o+w*0.64),fill=(238,196,74))
    d.line([(tip,o+w*0.36),(length-170,o+w*0.36)],fill=GOLDD,width=6); d.line([(tip,o+w*0.64),(length-170,o+w*0.64)],fill=GOLDD,width=6)
    d.rectangle((length-170,o,length-80,o+w),fill=STEEL); d.line([(length-125,o),(length-125,o+w)],fill=STEELD,width=8)
    d.rounded_rectangle((length-90,o,length,o+w),radius=40,fill=(214,120,120))
    d.polygon([(tip,o),(0,o+w/2),(tip,o+w)],fill=WOOD); d.polygon([(66,o+w/2-30),(0,o+w/2),(66,o+w/2+30)],fill=INK)
    return im
def club(length=1900):
    H=640; im=Image.new("RGBA",(length,H),(0,0,0,0)); d=ImageDraw.Draw(im); cy=H/2
    d.rounded_rectangle((length-500,cy-44,length,cy+44),radius=30,fill=BLACK)
    for x in range(length-480,length-20,70): d.line([(x,cy-44),(x+40,cy+44)],fill=(60,64,60),width=10)
    d.polygon([(300,cy-16),(length-500,cy-28),(length-500,cy+28),(300,cy+16)],fill=STEEL)
    d.line([(300,cy-5),(length-500,cy-11)],fill=(232,236,238),width=8)
    head=[(310,cy-26),(338,cy+36),(306,cy+250),(40,cy+276),(4,cy+206),(24,cy+50)]
    d.polygon(head,fill=STEEL,outline=STEELD)
    for k in range(4): d.line([(56,cy+105+k*38),(300,cy+88+k*38)],fill=STEELD,width=7)
    return im
def paste_rot(base,layer,angle,center):
    r=layer.rotate(angle,expand=True,resample=Image.BICUBIC)
    base.paste(r,(int(center[0]-r.width/2),int(center[1]-r.height/2)),r)
def bez(p0,p1,p2,n=50): return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0],(1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in [i/n for i in range(n+1)]]
def shield(cx,top,w,h):
    l,r=cx-w/2,cx+w/2; side=top+h*0.48; bot=top+h
    return [(l,top),(r,top),(r,side)]+bez((r,side),(r,side+(bot-side)*0.72),(cx,bot))[1:]+bez((cx,bot),(l,side+(bot-side)*0.72),(l,side))[1:]
def make(banner, name):
    im=grad(G2,G1); cx=1024; cyx=1090
    paste_rot(im,club(),45,(cx,cyx))
    paste_rot(im,pencil().transpose(Image.FLIP_LEFT_RIGHT),-45,(cx,cyx))
    top,w,h=420,960,1240
    sh=Image.new("RGBA",(S,S),(0,0,0,0)); ImageDraw.Draw(sh).polygon([(x+16,y+28) for x,y in shield(cx,top,w,h)],fill=(0,0,0,95)); im.paste(sh,(0,0),sh)
    d=ImageDraw.Draw(im)
    d.polygon(shield(cx,top,w,h),fill=GOLD)
    d.polygon(shield(cx,top+36,w-72,h-84),fill=CREAM)
    d.rectangle((cx-(w-72)/2,top+36,cx+(w-72)/2,top+190),fill=GD)
    for k in (-1,0,1): x=cx+k*150; d.ellipse((x-24,top+90,x+24,top+138),fill=CREAM)
    q=500; qy=top+260
    d.rectangle((cx-q/2,qy,cx+q/2,qy+q),outline=GD,width=56)
    d.text((cx,qy+q/2+10),"5",font=font(450),fill=GD,anchor="mm")
    if banner:
        by=top+h-300; bw=1220; bh=165
        for side in (-1,1):
            x=cx+side*(bw/2-20); d.polygon([(x,by+44),(x+side*190,by+44),(x+side*120,by+bh/2+44),(x+side*190,by+bh+44),(x,by+bh+44)],fill=GOLDD)
        d.rounded_rectangle((cx-bw/2,by,cx+bw/2,by+bh),radius=14,fill=GOLD)
        d.text((cx,by+bh/2+4),"BOGEY CLUB",font=font(136),fill=G1,anchor="mm")
    im.resize((OUT,OUT),Image.LANCZOS).save(name)
make(True,"Wappen_mit_Band.png"); make(False,"Wappen_ohne_Band.png")
sheet=Image.new("RGB",(2*420+3*50,600),(250,250,247)); sd=ImageDraw.Draw(sheet)
for i,(fn,lab) in enumerate([("Wappen_mit_Band.png","mit Schriftband"),("Wappen_ohne_Band.png","ohne Schriftband")]):
    x=50+i*470
    ic=Image.open(fn).resize((420,420),Image.LANCZOS); m=Image.new("L",(420,420),0); ImageDraw.Draw(m).rounded_rectangle((0,0,419,419),radius=92,fill=255)
    sheet.paste(ic,(x,30),m); sd.text((x+210,480),lab,font=font(36),fill=(40,50,44),anchor="mm")
    sm=Image.open(fn).resize((60,60),Image.LANCZOS); m2=Image.new("L",(60,60),0); ImageDraw.Draw(m2).rounded_rectangle((0,0,59,59),radius=13,fill=255)
    sheet.paste(sm,(x+180,515),m2)
sheet.save("BogeyClub-Wappen.png"); print("ok")
