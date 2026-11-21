#!/usr/bin/env python3
"""Overlay only the signed companion onto both pinned user baselines."""
import copy
import gzip
import hashlib
import io
import lzma
import plistlib
import re
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0"
PACKAGE_ID = "com.ning.controlcenter18"
LEGACY_PACKAGE_ID = "com.evgeniy558.controlcenter18"
BASELINES = (
    ("arm64", "var/jb/", "7968755fa82cc144c15c7b26253a44080439f24c37b9ae2eee1767b0443f6504"),
    ("arm64e", "", "200611c76e39a25f8a5c925e9f7161f1af02c507411966b1563d8aa4e8861b7f"),
)
XZ_FILTERS = [{"id": lzma.FILTER_LZMA2, "preset": 9 | lzma.PRESET_EXTREME,
               "dict_size": 32 * 1024 * 1024}]
SLIM_REMOVE_SUFFIXES = (".png", ".jpg", ".jpeg")


def slim_remove(name):
    # RootHide paths start at Library; rootless paths include var/jb/.
    return (("/Library/Application Support/ControlCenter18/Settings18/" in name or
             name.startswith("Library/Application Support/ControlCenter18/Settings18/")) or
            ("/Library/Application Support/ControlCenter18/AVControls18.bundle/Mic Modes Visualizer.ca/" in name or
             name.startswith("Library/Application Support/ControlCenter18/AVControls18.bundle/Mic Modes Visualizer.ca/")))


def deb_members(blob):
    assert blob[:8] == b"!<arch>\n", "Invalid ar header"
    offset, members = 8, {}
    while offset < len(blob):
        header = blob[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b"`\n", "Invalid ar member"
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58])
        offset += 60
        assert size >= 0 and offset + size <= len(blob) and name not in members
        members[name] = blob[offset:offset + size]
        offset += size + size % 2
    assert offset == len(blob) and members.get("debian-binary") == b"2.0\n"
    assert len(members) == 3, "Expected a three-member deb"
    return members


def archive(blob):
    entries = {}
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as tar:
        for info in tar:
            name = info.name.removeprefix("./")
            assert not name.startswith("/") and ".." not in Path(name).parts, name
            assert name not in entries, name
            content = tar.extractfile(info).read() if info.isfile() else None
            entries[name] = (copy.copy(info), content)
    return entries


def replace_content(entries, name, content):
    info = copy.copy(entries[name][0])
    assert info.isfile(), name
    info.size = len(content)
    entries[name] = (info, content)


def install_power_helper(entries, prefix, content):
    """Use explicit tar ownership; the build runner's user must not leak in."""
    for folder in ('usr', 'usr/libexec'):
        name = prefix + folder
        if name not in entries:
            info = tarfile.TarInfo(name)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.uid = info.gid = 0
            info.uname, info.gname = 'root', 'wheel'
            entries[name] = (info, None)
        assert entries[name][0].isdir(), name
    name = prefix + 'usr/libexec/C18PowerHelper'
    assert name not in entries, 'Unexpected preexisting power helper'
    info = tarfile.TarInfo(name)
    info.mode = 0o4755
    info.uid = info.gid = 0
    info.uname, info.gname = 'root', 'wheel'
    info.size = len(content)
    entries[name] = (info, content)
    return name


def serialize(entries, compressed=False):
    """Keep original TarInfo; write directories before files and symlinks."""
    assert not any(info.islnk() for info, _ in entries.values()), "Unexpected hardlink"
    names = sorted(entries, key=lambda name: (
        not entries[name][0].isdir(),
        name.count("/") if entries[name][0].isdir() else 0,
        name,
    ))
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in names:
            info, content = entries[name]
            info = copy.copy(info)
            info.pax_headers = {}
            tar.addfile(info, io.BytesIO(content) if info.isfile() else None)
    raw = buf.getvalue()
    return gzip.compress(raw, compresslevel=9, mtime=0) if compressed else raw


def compress_data(raw):
    compressed = lzma.compress(raw, format=lzma.FORMAT_XZ,
                               check=lzma.CHECK_CRC64, filters=XZ_FILTERS)
    assert lzma.decompress(compressed, memlimit=40 * 1024 * 1024) == raw
    return compressed


def write_deb(path, control, data):
    members = (("debian-binary", b"2.0\n"),
               ("control.tar.gz", control), ("data.tar.xz", data))
    with path.open("wb") as out:
        out.write(b"!<arch>\n")
        for name, content in members:
            header = (f"{name + '/':<16}{0:<12}{0:<6}{0:<6}"
                      f"{'100644':<8}{len(content):<10}`\n").encode("ascii")
            assert len(header) == 60
            out.write(header)
            out.write(content)
            if len(content) % 2:
                out.write(b"\n")


def main():
    companion = (ROOT / "build/C18ConnectivityFive.dylib").read_bytes()
    assert companion, "Missing signed companion content"
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    for arch, prefix, digest in BASELINES:
        baseline = (ROOT / f"Vendor/baseline-{arch}.deb").read_bytes()
        assert hashlib.sha256(baseline).hexdigest() == digest, f"Wrong {arch} baseline"
        members = deb_members(baseline)
        control_names = [name for name in members if name.startswith("control.tar")]
        data_names = [name for name in members if name.startswith("data.tar")]
        assert len(control_names) == len(data_names) == 1
        control, data = archive(members[control_names[0]]), archive(members[data_names[0]])
        original = dict(data)
        slim_removed = {name for name in data if slim_remove(name)}
        for name in slim_removed:
            del data[name]
        assert slim_removed, "Slimming rule removed nothing"
        folder = prefix + "Library/MobileSubstrate/DynamicLibraries/"
        target = folder + "C18ConnectivityFive.dylib"
        old_power = {folder + "C18PowerMenu.dylib", folder + "C18PowerMenu.plist"}
        if arch == "arm64e":
            old_power.add(folder + "C18PowerMenu.dylib.roothidepatch")
        assert target not in data and not old_power.intersection(data), "Sanitized inputs contain obsolete providers"
        companion_info = tarfile.TarInfo(target)
        companion_info.mode = 0o755
        companion_info.uid = companion_info.gid = 0
        companion_info.uname, companion_info.gname = 'root', 'wheel'
        companion_info.size = len(companion)
        data[target] = (companion_info, companion)
        before_helper = set(data)
        helper = install_power_helper(data, prefix, (ROOT / 'build/C18PowerHelper').read_bytes())
        helper_added = set(data) - before_helper
        cores = set()
        core_reports = __import__('json').loads((ROOT / 'build/core-signing.json').read_text())
        for stem in ('ControlCenter18', 'ControlCenter18Modules'):
            core = folder + stem + '.dylib'
            core_record = next(row for row in core_reports if row['arch'] == arch and row['stem'] == stem)
            signed_core = (ROOT / 'build' / core_record['file']).read_bytes()
            assert hashlib.sha256(signed_core).hexdigest() == core_record['signed_sha256']
            assert core_record['runtime_sections_unchanged'] and core_record['macos_codesign_strict_all_architectures']
            replace_content(data, core, signed_core)
            cores.add(core)
        settings_added = set()
        for filename, source, mode in (
            ('C18FourSettings.dylib', ROOT/'build/C18FourSettings.dylib', 0o755),
            ('C18FourSettings.plist', ROOT/'Settings/C18FourSettings.plist', 0o644),
        ):
            name = folder + filename
            assert name not in data
            content = source.read_bytes()
            info = tarfile.TarInfo(name)
            info.uid = info.gid = 0
            info.uname, info.gname = 'root', 'wheel'
            info.mode, info.size = mode, len(content)
            data[name] = (info, content)
            settings_added.add(name)
        from sileo_icon import install as install_sileo_icon
        sileo_added=install_sileo_icon(data,prefix)
        assert data.keys() == (original.keys() - slim_removed) | helper_added | {target} | settings_added | sileo_added
        from retained_modules import verify_retained_entries
        verify_retained_entries(data, prefix)
        assert all(data[name] == original[name] for name in data if name not in ({target} | cores | settings_added | helper_added | sileo_added)), "Overlay escaped reviewed scope"
        from test_settings import verify_settings_entries
        verify_settings_entries(data, prefix, require_adapter=True)
        helper_info, helper_bytes = data[helper]
        assert helper_info.uid == helper_info.gid == 0 and helper_info.mode == 0o4755
        assert helper_bytes == (ROOT / 'build/C18PowerHelper').read_bytes()

        # Compute this only after all payload changes; preserve every other control byte.
        old_control = control["control"][1]
        fields = dict(line.split(b":", 1) for line in old_control.splitlines()
                      if b":" in line and not line.startswith((b" ", b"\t")))
        assert fields[b"Version"].strip() == VERSION.encode()
        assert fields[b"Architecture"].strip() == f"iphoneos-{arch}".encode()
        installed_size = (sum(len(content) for _, content in data.values()
                              if content is not None) + 1023) // 1024
        new_control, count = re.subn(br"(?m)^Installed-Size:[^\r\n]*",
                                    f"Installed-Size: {installed_size}".encode(), old_control)
        assert count == 1, "Expected exactly one Installed-Size field"
        # User-requested metadata only. Keep Name, preference domains, module
        # identifiers and injected paths unchanged; prevent dual engine loads.
        for key,value in (("Package",PACKAGE_ID),("Author","Ning"),("Maintainer","Ning")):
            new_control,n=re.subn(rb"(?m)^"+key.encode()+rb":[^\r\n]*",(key+": "+value).encode(),new_control)
            assert n==1,key
        for key in ("Conflicts","Replaces","Provides"):
            existing=fields.get(key.encode(),b"").decode().strip()
            values=[v.strip() for v in existing.split(',') if v.strip()]
            if LEGACY_PACKAGE_ID not in values:values.append(LEGACY_PACKAGE_ID)
            line=(key+": "+', '.join(values)).encode()
            if key.encode() in fields:new_control,n=re.subn(rb"(?m)^"+key.encode()+rb":[^\r\n]*",line,new_control);assert n==1
            else:new_control=new_control.rstrip(b'\n')+b'\n'+line+b'\n'
        from sileo_icon import replace_icon_field, verify as verify_sileo_icon
        new_control=replace_icon_field(new_control,prefix)
        verify_sileo_icon(data,prefix,new_control)
        replace_content(control, "control", new_control)
        out = dist / f"{PACKAGE_ID}_{VERSION}_iphoneos-{arch}.deb"
        write_deb(out, serialize(control, compressed=True), compress_data(serialize(data)))
        print(out.relative_to(ROOT), out.stat().st_size, hashlib.sha256(out.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
