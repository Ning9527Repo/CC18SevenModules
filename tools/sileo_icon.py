"""Selected D icon for package-manager metadata only; never changes UI assets."""
from pathlib import Path
import hashlib,json,struct,tarfile
ROOT=Path(__file__).resolve().parents[1]
ICON_FOLDER=ROOT/'Resources/SileoIcon'
ICON_STEM='com.ning.controlcenter18'
MASTER_SHA256='3239e6a61cede3b52fde41eb9a8140df1013617a2623e2456f852294beecb533'

def assets():
 manifest=json.loads((ICON_FOLDER/'manifest.json').read_text())
 assert manifest['selection']=='D-vivid-18-original'
 assert manifest['master_sha256']==MASTER_SHA256
 result={}
 for row in manifest['assets']:
  size=row['size'];assert size in (512,256,128) and size not in result
  assert row['file']==f'PackageIcon-{size}.png'
  content=(ICON_FOLDER/row['file']).read_bytes()
  assert hashlib.sha256(content).hexdigest()==row['sha256']
  assert content[:8]==b'\x89PNG\r\n\x1a\n' and content[12:16]==b'IHDR'
  assert struct.unpack_from('>IIBB',content,16)==(size,size,8,6)
  if size==512:assert row['sha256']==MASTER_SHA256
  result[size]=content
 assert set(result)=={512,256,128}
 return result

def installed_paths(prefix):
 return {size:prefix+'usr/share/icons/'+ICON_STEM+('' if size==512 else f'-{size}')+'.png' for size in (512,256,128)}

def replace_icon_field(metadata,prefix):
 # Remove the legacy case-insensitive field, not a fallback or a second Icon.
 lines=[];dropping=False
 for line in metadata.splitlines():
  if line.startswith((b' ',b'\t')):
   if not dropping:lines.append(line)
   continue
  dropping=line.split(b':',1)[0].lower()==b'icon' and b':' in line
  if not dropping:lines.append(line)
 lines.append(b'Icon: file:///'+installed_paths(prefix)[512].encode())
 return b'\n'.join(lines)+b'\n'

def install(entries,prefix):
 before=set(entries)
 for folder in ('usr','usr/share','usr/share/icons'):
  name=prefix+folder
  if name not in entries:
   info=tarfile.TarInfo(name);info.type=tarfile.DIRTYPE;info.mode=0o755
   info.uid=info.gid=0;info.uname,info.gname='root','wheel';entries[name]=(info,None)
  assert entries[name][0].isdir()
 paths=installed_paths(prefix)
 for size,content in assets().items():
  name=paths[size];assert name not in entries,'unexpected preexisting package icon'
  info=tarfile.TarInfo(name);info.mode=0o644;info.size=len(content)
  info.uid=info.gid=0;info.uname,info.gname='root','wheel';entries[name]=(info,content)
 return set(entries)-before

def verify(entries,prefix,metadata):
 paths=installed_paths(prefix);icons=assets()
 for size,name in paths.items():
  info,content=entries[name]
  assert info.isfile() and info.mode==0o644 and info.uid==info.gid==0
  assert content==icons[size]
 actual={name for name in entries if name.startswith(prefix+'usr/share/icons/'+ICON_STEM) and entries[name][0].isfile()}
 assert actual==set(paths.values()),'unexpected old/fallback package icon'
 fields=[line for line in metadata.splitlines() if line.split(b':',1)[0].lower()==b'icon' and b':' in line]
 assert fields==[b'Icon: file:///'+paths[512].encode()],'single new local icon field required'
 return {'selection':'D-vivid-18-original','sizes':[512,256,128],'icon':fields[0].decode(),'legacy_reference_removed':True,'scope':'Sileo only'}
