"""Read Microsoft package ZIP directories using bounded HTTP range reads."""
import io, urllib.request, zipfile, json, struct, sys
from pathlib import Path

URL='https://windbg.download.prss.microsoft.com/dbazure/prod/1-2606-22001-0/windbg.msixbundle'
DEST=Path(__file__).resolve().parent/'h3-comparison/diagnostics'

class RemoteFile(io.RawIOBase):
    def __init__(self,url,size=None,offset=0):
        self.url=url;self.offset=offset;self.pos=0
        if size is None:
            with urllib.request.urlopen(urllib.request.Request(url,method='HEAD'),timeout=30) as r:
                size=int(r.headers['Content-Length'])
        self.size=size
    def readable(self):return True
    def seekable(self):return True
    def tell(self):return self.pos
    def seek(self,n,whence=0):
        self.pos=n if whence==0 else self.pos+n if whence==1 else self.size+n
        return self.pos
    def read(self,n=-1):
        n=min(self.size-self.pos,n if n>=0 else self.size-self.pos)
        if n<=0:return b''
        if n>32*1024*1024:raise ValueError('Bounded read exceeded 32 MiB')
        start=self.offset+self.pos
        req=urllib.request.Request(self.url,headers={'Range':f'bytes={start}-{start+n-1}'})
        with urllib.request.urlopen(req,timeout=60) as r:
            if r.status!=206:raise RuntimeError('Server did not honor bounded range request')
            data=r.read(n)
        self.pos+=len(data);return data

if __name__=='__main__':
    DEST.mkdir(exist_ok=True)
    z=zipfile.ZipFile(RemoteFile(URL))
    entries=[{'name':v.filename,'size':v.file_size,'compressed':v.compress_size,'offset':v.header_offset,'method':v.compress_type} for v in z.infolist()]
    (DEST/'official-debugger-package.json').write_text(json.dumps(entries,indent=2))
    print(json.dumps(entries,indent=2))
    package=z.getinfo('windbg_win-x64.msix')
    if package.compress_type!=zipfile.ZIP_STORED:raise RuntimeError('Nested package is compressed')
    outer=RemoteFile(URL);outer.seek(package.header_offset)
    header=outer.read(30);name_len,extra_len=struct.unpack_from('<HH',header,26)
    offset=package.header_offset+30+name_len+extra_len
    nested=zipfile.ZipFile(RemoteFile(URL,package.file_size,offset))
    names=[{'name':v.filename,'size':v.file_size,'compressed':v.compress_size} for v in nested.infolist()]
    (DEST/'official-debugger-x64-files.json').write_text(json.dumps(names,indent=2))
    print('\n'.join(v['name'] for v in names if '/cdb.exe' in v['name'] or v['name'].lower().endswith('/dbgeng.dll')))
    if '--fetch-minimal' in sys.argv:
        chosen=[v for v in nested.infolist() if v.filename.startswith('amd64/') and (
            v.filename.count('/')==1 and v.filename.endswith(('.dll','cdb.exe'))
            or v.filename in ('amd64/winext/ext.dll','amd64/winext/uext.dll','amd64/winext/kext.dll')
            or v.filename.startswith('amd64/winxp/') and v.filename.endswith('.dll'))]
        target=DEST/'microsoft-debugger'
        for v in chosen:
            path=target/v.filename
            if path.exists() and path.stat().st_size==v.file_size:continue
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(nested.read(v))
            print('DOWNLOADED',v.filename,v.file_size,flush=True)
