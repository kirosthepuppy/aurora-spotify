#!/usr/bin/env python3
"""Package a user-supplied decrypted arm64 Spotify IPA with Aurora. Stdlib only.

Adds a load command only when existing zeroed header padding is sufficient.
It never shifts Mach-O data, decrypts binaries, or signs the result.
"""
from __future__ import annotations
import argparse
import copy
import os
from pathlib import Path, PurePosixPath
import plistlib
import struct
import tempfile
import zipfile

DYLIB_PATH = '@executable_path/Frameworks/Aurora.dylib'
MAX_ENTRY = 1024 * 1024 * 1024
MAX_TOTAL = 4 * MAX_ENTRY

class PackageError(ValueError):
    pass

def commands(binary: bytes):
    if len(binary) < 32 or binary[:4] != b'\xcf\xfa\xed\xfe':
        raise PackageError('Expected a thin, little-endian 64-bit Mach-O. Universal/fat inputs must be thinned first.')
    _, cpu, _, _, count, size, _, _ = struct.unpack_from('<8I', binary)
    if cpu != 0x0100000C:
        raise PackageError('Only arm64 Mach-O is supported.')
    if size > len(binary)-32 or count > size//8:
        raise PackageError('Invalid Mach-O load-command table.')
    position=32
    found=[]
    for _ in range(count):
        if position+8>32+size:
            raise PackageError('Truncated load command.')
        cmd,length=struct.unpack_from('<II',binary,position)
        if length<8 or length%8 or position+length>32+size:
            raise PackageError('Invalid load-command size.')
        found.append((cmd,position,length))
        position+=length
    if position != 32+size:
        raise PackageError('Load-command count and size disagree.')
    return found

def validate_decrypted(binary: bytes):
    found=commands(binary)
    for cmd,start,length in found:
        if cmd in (0x21,0x2C):
            if length < (24 if cmd==0x2C else 20):
                raise PackageError('Malformed encryption command.')
            if struct.unpack_from('<I',binary,start+16)[0]:
                raise PackageError('The executable is encrypted. Supply your own already-decrypted IPA; this tool does not decrypt apps.')
    return found

def inject(binary: bytes) -> bytes:
    found=validate_decrypted(binary)
    _,_,_,filetype,count,old_size,_,_=struct.unpack_from('<8I',binary)
    if filetype != 2:
        raise PackageError('The app executable must be MH_EXECUTE.')
    first_data=len(binary)
    has_section=False
    for cmd,start,length in found:
        if cmd in (0xC,0x18|0x80000000,0x1F|0x80000000):
            if length<24:
                raise PackageError('Malformed dylib command.')
            name_offset=struct.unpack_from('<I',binary,start+8)[0]
            if name_offset<24 or name_offset>=length:
                raise PackageError('Malformed dylib name offset.')
            if binary[start+name_offset:start+length].split(b'\0',1)[0].decode('utf-8',errors='replace')==DYLIB_PATH:
                raise PackageError('Aurora is already injected. Start with an unmodified IPA.')
        if cmd==0x19:  # LC_SEGMENT_64
            if length<72:
                raise PackageError('Malformed segment command.')
            fileoff,filesize=struct.unpack_from('<QQ',binary,start+40)
            nsects=struct.unpack_from('<I',binary,start+64)[0]
            if length!=72+80*nsects or fileoff+filesize>len(binary):
                raise PackageError('Malformed segment or section bounds.')
            if fileoff>0 and filesize>0:
                first_data=min(first_data,fileoff)
            for n in range(nsects):
                section=start+72+n*80
                section_size=struct.unpack_from('<Q',binary,section+40)[0]
                offset=struct.unpack_from('<I',binary,section+48)[0]
                flags=struct.unpack_from('<I',binary,section+64)[0]
                if flags&0xFF not in (1,0xC,0x12) and section_size:
                    if offset<32+old_size or offset+section_size>len(binary):
                        raise PackageError('Invalid section data bounds.')
                    has_section=True
                    first_data=min(first_data,offset)
    name=DYLIB_PATH.encode()+b'\0'
    new_size=(24+len(name)+7)&~7
    insertion=32+old_size
    if not has_section or insertion+new_size>first_data or any(binary[insertion:insertion+new_size]):
        raise PackageError('Not enough verified zeroed Mach-O header padding. Use a mature injector such as cyan; no offsets were modified.')
    command=struct.pack('<6I',0xC,new_size,24,0,0x10000,0x10000)+name
    command=command.ljust(new_size,b'\0')
    result=bytearray(binary)
    result[insertion:insertion+new_size]=command
    struct.pack_into('<II',result,16,count+1,old_size+new_size)
    return bytes(result)

def safe_name(name: str):
    path=PurePosixPath(name)
    if not name or name.startswith('/') or '\\' in name or '..' in path.parts or '\x00' in name:
        raise PackageError('Unsafe path in IPA archive.')

def package(ipa: Path,dylib: Path,output: Path):
    if ipa.resolve()==output.resolve():
        raise PackageError('Output must differ from input.')
    library=dylib.read_bytes()
    validate_decrypted(library)
    filetype=struct.unpack_from('<I',library,12)[0]
    if filetype!=6:
        raise PackageError('Aurora must be a Mach-O dynamic library (MH_DYLIB).')
    with zipfile.ZipFile(ipa) as source:
        entries=source.infolist()
        names=[entry.filename for entry in entries]
        if len(set(names))!=len(names):
            raise PackageError('Duplicate paths in IPA archive.')
        if len(entries)>100000 or sum(e.file_size for e in entries)>MAX_TOTAL or any(e.file_size>MAX_ENTRY for e in entries):
            raise PackageError('IPA exceeds packaging limits.')
        for name in names:
            safe_name(name)
        candidates=[n for n in names if n.startswith('Payload/') and len(PurePosixPath(n).parts)==3 and n.endswith('.app/Info.plist')]
        if len(candidates)!=1:
            raise PackageError('Expected exactly one top-level Payload/*.app/Info.plist.')
        info_path=candidates[0];info=plistlib.loads(source.read(info_path))
        if info.get('CFBundleIdentifier')!='com.spotify.client':
            raise PackageError('Input must have bundle identifier com.spotify.client.')
        executable=info.get('CFBundleExecutable')
        if not isinstance(executable,str) or not executable or '/' in executable or '\\' in executable or executable in ('.','..'):
            raise PackageError('Invalid CFBundleExecutable.')
        app=info_path.removesuffix('Info.plist')
        main=app+executable
        if main not in names:
            raise PackageError('App executable missing from IPA.')
        patched=inject(source.read(main))
        target=app+'Frameworks/Aurora.dylib'
        if target in names:
            raise PackageError('Aurora.dylib already exists in the IPA.')
        output.parent.mkdir(parents=True,exist_ok=True)
        fd,temp=tempfile.mkstemp(prefix='.aurora-',suffix='.ipa',dir=output.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(temp,'w',compression=zipfile.ZIP_DEFLATED,allowZip64=True) as destination:
                for entry in entries:
                    if '/_CodeSignature/' in entry.filename or entry.filename.endswith('/embedded.mobileprovision'):
                        continue
                    metadata=copy.copy(entry)
                    destination.writestr(metadata,patched if entry.filename==main else source.read(entry))
                metadata=zipfile.ZipInfo(target)
                metadata.create_system=3
                metadata.external_attr=0o100755<<16
                metadata.compress_type=zipfile.ZIP_DEFLATED
                destination.writestr(metadata,library)
            os.replace(temp,output)
        finally:
            if os.path.exists(temp):os.unlink(temp)
    return output

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa',type=Path,required=True)
    parser.add_argument('--dylib',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        path=package(args.ipa,args.dylib,args.output)
    except (PackageError,OSError,zipfile.BadZipFile,plistlib.InvalidFileException) as error:
        parser.exit(1,f'Packaging failed: {error}\n')
    print(f'Created {path} (unsigned; sign before installing).')

if __name__=='__main__':main()
