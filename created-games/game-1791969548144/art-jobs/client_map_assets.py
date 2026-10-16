"""Read-only NetDragon package index inspection and selected asset extraction.
No client executable/DLL is loaded. All outputs stay in the specified project job.
"""
from pathlib import Path
import struct, zlib, json, hashlib

ROOT=Path(r'Z:\Program Files (x86)\NetDragon\魔域')
JOB=Path(__file__).resolve().parent/'client-canosa-20261015'
JOB.mkdir(exist_ok=True)

def index(path):
    data=path.read_bytes()
    assert data.startswith(b'NetDragonDatPkg\0')
    p=48
    result={}
    while p<len(data):
        length=data[p]; p+=1
        name=data[p:p+length].decode('gb18030');p+=length
        count,total,packed=struct.unpack_from('<HII',data,p);p+=10
        assert 0<count<20000
        blocks=[struct.unpack_from('<III',data,p+i*12) for i in range(count)]
        p+=count*12
        result[name.lower()]=(path.with_suffix('.tpd'),total,blocks)
    assert p==len(data)
    return result

def extract(record):
    path,total,blocks=record
    pieces=[]
    with path.open('rb') as stream:
        for size,raw,offset in blocks:
            stream.seek(offset); value=stream.read(size)
            part=zlib.decompress(value) if size!=raw else value
            assert len(part)==raw
            pieces.append(part)
    data=b''.join(pieces)
    assert len(data)==total
    return data

if __name__=='__main__':
    records={}
    for path in [ROOT/'map.tpi',*sorted(ROOT.glob('data*.tpi'))]:
        records.update(index(path))
    names=[name for name in records if any(s in name for s in ['chamgw26','minimap/1000','minimap/1000.','bigmap/1000','map1000','canosa'])]
    (JOB/'candidates.json').write_text(json.dumps({n:{'pack':str(records[n][0]),'size':records[n][1]} for n in names},ensure_ascii=False,indent=2),encoding='utf-8')
    (JOB/'asset-index.json').write_text(json.dumps({n:[str(r[0]),r[1],r[2]] for n,r in records.items()},ensure_ascii=False),encoding='utf-8')
    for name in names:
        data=extract(records[name]); dest=JOB/'source'/name
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
    print(json.dumps({'indexed':len(records),'candidates':names},ensure_ascii=False))
