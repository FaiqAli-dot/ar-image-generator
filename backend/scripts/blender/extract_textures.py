import json,struct,os,io,sys
from PIL import Image
g,o=sys.argv[1],sys.argv[2];d=open(g,'rb').read();l=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+l]);b=20+l+8
os.makedirs(o,exist_ok=True);info=[]
for i,im in enumerate(j['images']):
  bv=j['bufferViews'][im['bufferView']];s=b+bv.get('byteOffset',0);raw=d[s:s+bv['byteLength']]
  p=f'{o}/tex_{i:02d}.png';open(p,'wb').write(raw);I=Image.open(io.BytesIO(raw))
  info.append(dict(path=p,mime=im['mimeType'],width=I.width,height=I.height,mode=I.mode,bytes=len(raw),purpose='baseColor UV atlas'))
json.dump(info,open(f'{o}/textures.json','w'),indent=1)
S=Image.new('RGB',(8*256,((len(info)+7)//8)*256),'white')
for i,x in enumerate(info):S.paste(Image.open(x['path']).convert('RGB').resize((256,256)),(i%8*256,i//8*256))
S.save(f'{o}/contact_sheet.png')
