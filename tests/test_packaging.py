import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec=importlib.util.spec_from_file_location('package_ipa',Path(__file__).resolve().parents[1]/'scripts/package_ipa.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

def macho(*,encrypted=False,padding=True,filetype=2):
    # A real arm64 Mach-O layout: header, __TEXT segment with one section,
    # encryption info, zero header padding, then section data.
    commands_size=152+24
    section_offset=512 if padding else 32+commands_size
    header=struct.pack('<8I',0xFEEDFACF,0x0100000C,0,filetype,2,commands_size,0,0)
    segment=struct.pack('<II16sQQQQIIII',0x19,152,b'__TEXT',0,1024,0,1024,7,5,1,0)
    section=struct.pack('<16s16sQQIIIIIIII',b'__text',b'__TEXT',section_offset,32,section_offset,2,0,0,0x80000400,0,0,0)
    encryption=struct.pack('<6I',0x2C,24,section_offset,32,int(encrypted),0)
    binary=bytearray((header+segment+section+encryption).ljust(1024,b'\0'))
    binary[section_offset:section_offset+32]=b'\xA5'*32
    return bytes(binary)

class InjectionTests(unittest.TestCase):
    def test_adds_load_without_moving_code(self):
        original=macho();patched=p.inject(original)
        self.assertEqual(len(patched),len(original))
        self.assertEqual(patched[512:],original[512:])
        self.assertIn(p.DYLIB_PATH.encode(),patched[:512])
        self.assertEqual(struct.unpack_from('<I',patched,16)[0],3)
        self.assertEqual(len(p.commands(patched)),3)
    def test_rejects_encrypted_executable(self):
        with self.assertRaisesRegex(p.PackageError,'encrypted'):p.inject(macho(encrypted=True))
    def test_rejects_insufficient_padding(self):
        with self.assertRaisesRegex(p.PackageError,'padding'):p.inject(macho(padding=False))
    def test_rejects_nonzero_padding(self):
        binary=bytearray(macho());binary[208]=1
        with self.assertRaisesRegex(p.PackageError,'padding'):p.inject(binary)
    def test_rejects_reinjection(self):
        with self.assertRaisesRegex(p.PackageError,'already injected'):p.inject(p.inject(macho()))
    def test_rejects_truncated_command(self):
        binary=bytearray(macho());struct.pack_into('<I',binary,36,999999)
        with self.assertRaises(p.PackageError):p.inject(binary)
    def test_rejects_fat_input(self):
        with self.assertRaisesRegex(p.PackageError,'thin'):p.inject(b'\xca\xfe\xba\xbe'+b'\0'*100)
    def test_rejects_wrong_arch(self):
        binary=bytearray(macho());struct.pack_into('<I',binary,4,0x01000007)
        with self.assertRaisesRegex(p.PackageError,'arm64'):p.inject(binary)
    def test_rejects_section_past_end(self):
        binary=bytearray(macho());struct.pack_into('<Q',binary,32+72+40,5000)
        with self.assertRaisesRegex(p.PackageError,'bounds'):p.inject(binary)

class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.ipa=self.root/'input.ipa';self.dylib=self.root/'Aurora.dylib';self.out=self.root/'out.ipa'
        self.dylib.write_bytes(macho(filetype=6))
    def fixture(self,bundle='com.spotify.client',extra=None):
        with zipfile.ZipFile(self.ipa,'w') as archive:
            archive.writestr('Payload/Spotify.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleExecutable':'Spotify'}))
            metadata=zipfile.ZipInfo('Payload/Spotify.app/Spotify');metadata.external_attr=0o100755<<16
            archive.writestr(metadata,macho())
            archive.writestr('Payload/Spotify.app/_CodeSignature/CodeResources',b'old-signature')
            archive.writestr('Payload/Spotify.app/embedded.mobileprovision',b'old-profile')
            archive.writestr('Payload/Spotify.app/asset.dat',b'preserve-me')
            if extra:archive.writestr(extra,b'bad')
    def test_full_package_preserves_assets_and_permissions(self):
        self.fixture();before=self.ipa.read_bytes();p.package(self.ipa,self.dylib,self.out)
        self.assertEqual(self.ipa.read_bytes(),before)
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read('Payload/Spotify.app/asset.dat'),b'preserve-me')
            self.assertEqual(archive.read('Payload/Spotify.app/Frameworks/Aurora.dylib'),self.dylib.read_bytes())
            self.assertEqual(archive.getinfo('Payload/Spotify.app/Spotify').external_attr>>16,0o100755)
            self.assertNotIn('Payload/Spotify.app/_CodeSignature/CodeResources',archive.namelist())
            self.assertNotIn('Payload/Spotify.app/embedded.mobileprovision',archive.namelist())
    def test_rejects_path_traversal(self):
        self.fixture(extra='../outside')
        with self.assertRaisesRegex(p.PackageError,'Unsafe'):p.package(self.ipa,self.dylib,self.out)
        self.assertFalse(self.out.exists())
    def test_rejects_wrong_app(self):
        self.fixture(bundle='example.app')
        with self.assertRaisesRegex(p.PackageError,'com.spotify'):p.package(self.ipa,self.dylib,self.out)
    def test_rejects_overwrite_of_source(self):
        self.fixture()
        with self.assertRaisesRegex(p.PackageError,'differ'):p.package(self.ipa,self.dylib,self.ipa)
    def test_rejects_non_dylib_library(self):
        self.fixture();self.dylib.write_bytes(macho())
        with self.assertRaisesRegex(p.PackageError,'dynamic library'):p.package(self.ipa,self.dylib,self.out)

if __name__=='__main__':unittest.main()
