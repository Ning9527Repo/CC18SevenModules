"""Shared fat Mach-O slice parser; contains no preference-page implementation."""
import struct

def slices(data):
    assert struct.unpack_from('>II', data)==(0xcafebabe,2)
    result=[]
    for index in range(2):
        cpu,subtype,offset,size,alignment=struct.unpack_from('>5I',data,8+20*index)
        assert cpu==0x100000c and subtype in (0,0x80000002)
        assert offset+size<=len(data) and offset%(1<<alignment)==0
        assert struct.unpack_from('<3I',data,offset)==(0xfeedfacf,cpu,subtype)
        result.append((subtype,offset,size))
    assert {r[0] for r in result}=={0,0x80000002}
    return result
