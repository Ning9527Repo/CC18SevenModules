"""Only package icon assets/metadata may change; no iOS process is run."""
from pathlib import Path
import hashlib,json,struct
from package import ROOT,BASELINES,deb_members,archive,serialize
from sileo_icon import assets,install,replace_icon_field,verify,installed_paths

def main():
 source=(ROOT/'tools/package.py').read_text()
 assert 'sileo_added=install_sileo_icon(data,prefix)' in source
 assert 'new_control=replace_icon_field(new_control,prefix)' in source
 assert 'verify_sileo_icon(data,prefix,new_control)' in source
 assert 'sileo_added)), "Overlay escaped reviewed scope"' in source
 icons=assets();assert set(icons)=={512,256,128}
 # Verify PNG dimensions and transparent corners without a Pillow CI dependency.
 import zlib
 for size,blob in icons.items():
  at=8;compressed=b''
  while at<len(blob):
   length=struct.unpack_from('>I',blob,at)[0];kind=blob[at+4:at+8];body=blob[at+8:at+8+length]
   if kind==b'IDAT':compressed+=body
   at+=12+length
  raw=zlib.decompress(compressed);stride=size*4;last=bytearray(stride);rows=[]
  for y in range(size):
   at=y*(stride+1);f=raw[at];line=bytearray(raw[at+1:at+1+stride]);assert f<=4
   for x in range(stride):
    a=line[x-4] if x>=4 else 0;b=last[x];c=last[x-4] if x>=4 else 0
    if f==1:predict=a
    elif f==2:predict=b
    elif f==3:predict=(a+b)//2
    elif f==4:
     p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c);predict=a if pa<=pb and pa<=pc else b if pb<=pc else c
    else:predict=0
    line[x]=(line[x]+predict)&255
   if y in (0,size-1):rows.append(line)
   last=line
  assert all(row[3]==row[-1]==0 for row in rows),'corner alpha must remain transparent'
 reports=[]
 for arch,prefix,digest in BASELINES:
  baseline=(ROOT/f'Vendor/baseline-{arch}.deb').read_bytes();assert hashlib.sha256(baseline).hexdigest()==digest
  members=deb_members(baseline);data=archive(next(v for k,v in members.items() if k.startswith('data.tar')))
  control=archive(next(v for k,v in members.items() if k.startswith('control.tar')))
  before=dict(data);old=control['control'][1];added=install(data,prefix);metadata=replace_icon_field(old,prefix)
  assert data.keys()==before.keys()|added
  assert all(data[n]==value for n,value in before.items()),'existing file changed, including all module/UI glyphs'
  assert len([n for n in added if data[n][0].isfile()])==3
  assert all(n.startswith(prefix+'usr/share/icons/') or data[n][0].isdir() for n in added)
  assert verify(data,prefix,metadata)['legacy_reference_removed']
  assert replace_icon_field(metadata,prefix)==metadata,'replacement must be idempotent'
  def without_icon(b):return [line for line in b.splitlines() if not line.lower().startswith(b'icon:')]
  assert without_icon(old)==without_icon(metadata),'unrelated control metadata changed'
  # Roundtrip the actual tar serializer, without generating a deb or compiling.
  roundtrip=archive(serialize(data));assert roundtrip.keys()==data.keys()
  assert all(roundtrip[n][1]==data[n][1] for n in data)
  paths=installed_paths(prefix);bad=dict(data);info,content=bad[paths[512]];bad[paths[512]]=(info,content[:-1]+b'X')
  try:verify(bad,prefix,metadata)
  except AssertionError:pass
  else:raise AssertionError('bad asset accepted')
  for badmeta in (old,metadata+b'icon: https://example.invalid/old.png\n'):
   try:verify(data,prefix,badmeta)
   except AssertionError:pass
   else:raise AssertionError('old or duplicate icon accepted')
  reports.append({'arch':arch,'existing_payload_files_unchanged':sum(i.isfile() for i,b in before.values()),'new_icons':list(paths.values()),'old_reference_absent':True,'tar_roundtrip':True})
 print('SILEO_ICON_ONLY_OK',json.dumps(reports,ensure_ascii=False))
if __name__=='__main__':main()
