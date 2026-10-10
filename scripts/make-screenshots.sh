#!/bin/zsh
# Renders the README screenshots (docs/images/*-en.png and *-zh.png) from demo tasks,
# so no real folder names end up in them.
#
#   scripts/make-screenshots.sh
set -euo pipefail

ROOT=${0:A:h:h}
OUT=$ROOT/docs/images
DEMO=$(mktemp -d -t syncdock-demo)
trap 'rm -rf "$DEMO"' EXIT

xcodebuild -project "$ROOT/SyncDock.xcodeproj" -scheme SyncDock -configuration Debug \
    -derivedDataPath "$ROOT/build/DerivedData" build -quiet
APP=$ROOT/build/DerivedData/Build/Products/Debug/SyncDock.app/Contents/MacOS/SyncDock

# Demo tasks: launch agents, batch jobs and logs in $DEMO/<lang>.
/usr/bin/python3 -I - "$DEMO" "$HOME" <<'PY'
import os, sys, plistlib, datetime
demo, home = sys.argv[1], sys.argv[2]
now = datetime.datetime.now()
tasks = {
    "en": ["Photos to Backup Drive", "Documents to OneDrive", "Projects to Backup Drive"],
    "zh": ["照片-备份硬盘", "文稿-OneDrive", "项目-备份硬盘"],
}
specs = [  # source, target, schedule, keep .git, last run, items, size
    (f"{home}/Pictures/Photos", "/Volumes/Backup/Photos", {"Hour": 21, "Minute": 0}, False,
     now.replace(hour=9, minute=0) if now.hour >= 9 else now - datetime.timedelta(hours=1), 1284, "3.21 GB"),
    (f"{home}/Documents/Work", f"{home}/Library/CloudStorage/OneDrive-Personal/Work", {"Hour": 1, "Minute": 30},
     False, (now - datetime.timedelta(days=1)).replace(hour=1, minute=30), 0, "0 bytes"),
    (f"{home}/Desktop/Projects", "/Volumes/Backup/Projects",
     [{"Weekday": d, "Hour": 18, "Minute": 0} for d in (1, 4)], True,
     (now - datetime.timedelta(days=2)).replace(hour=18, minute=0), 342, "86.4 MB"),
]

def pair(src, dst, include=None, exclude=()):
    if include is None:
        return f"<Pair><Left>{src}</Left><Right>{dst}</Right></Pair>"
    items = "".join(f"<Item>{e}</Item>" for e in exclude)
    return (f"<Pair><Left>{src}</Left><Right>{dst}</Right><Filter><Include><Item>{include}</Item></Include>"
            f"<Exclude>{items}</Exclude><SizeMin Unit=\"None\">0</SizeMin><SizeMax Unit=\"None\">0</SizeMax>"
            f"<TimeSpan Type=\"None\">0</TimeSpan></Filter></Pair>")

for lang, names in tasks.items():
    agents, jobs, logs = (os.path.join(demo, lang, d) for d in ("agents", "jobs", "logs"))
    for d in (agents, jobs, logs): os.makedirs(d)
    for i, (name, (src, dst, sched, git, last, items, size)) in enumerate(zip(names, specs)):
        pairs = pair(src, dst, "*", ["*/.*"]) + pair(src, dst, "*/.git/", []) if git else pair(src, dst)
        global_exclude = "*/.DS_Store" if git else "*/.*"
        batch = os.path.join(jobs, name + ".ffs_batch")
        open(batch, "w").write(f'''<?xml version="1.0" encoding="utf-8"?>
<FreeFileSync XmlType="BATCH" XmlFormat="23"><Synchronize>
<Differences LeftOnly="right" LeftNewer="right" RightNewer="none" RightOnly="none"/></Synchronize>
<Filter><Include><Item>*</Item></Include><Exclude><Item>{global_exclude}</Item></Exclude></Filter>
<FolderPairs>{pairs}</FolderPairs></FreeFileSync>''')
        label = f"local.freefilesync.demo{i}"
        plistlib.dump({"Label": label, "ProgramArguments": ["/bin/sh", "-c", "true", "sh", "", batch],
                       "StartCalendarInterval": sched}, open(os.path.join(agents, label + ".plist"), "wb"))
        open(os.path.join(logs, f"{name} {last:%Y-%m-%d %H%M%S}.000.html"), "w").write(
            '<img src="https://freefilesync.org/images/log/result-succes.png">'
            '<table class="summary-table"><tr><td>Elements processed:</td>'
            '<td><img src="https://freefilesync.org/images/log/file.png" width="24" height="24" alt=""></td>'
            f'<td><span style="font-weight:600;">{items}</span> ({size})</td></tr></table>')
PY

mkdir -p "$OUT"
# 「完全磁盘访问权限已确认」用启动参数传入（只对这次运行生效），截图不依赖运行者自己的设置
render() { # lang appleLanguage name view
    SYNCDOCK_AGENTS=$DEMO/$1/agents SYNCDOCK_LOGS=$DEMO/$1/logs \
        "$APP" --snapshot "$DEMO/$3-$1.png" ${4:+"$4"} -AppleLanguages "($2)" \
        -fullDiskAccessVerifiedAt '<date>2026-01-01T00:00:00Z</date>'
}
for lang apple in en en zh zh-Hans; do
    render $lang $apple panel
    render $lang $apple editor local.freefilesync.demo2
    render $lang $apple setup setup
done

# Rounded corners, a soft shadow and transparent padding, like a window on screen.
/usr/bin/swift - "$DEMO" "$OUT" <<'SWIFT'
import AppKit
let (src, dst) = (CommandLine.arguments[1], CommandLine.arguments[2])
for file in try! FileManager.default.contentsOfDirectory(atPath: src) where file.hasSuffix(".png") {
    let image = NSImage(contentsOfFile: "\(src)/\(file)")!
    let rep = image.representations[0]
    let (w, h, pad) = (CGFloat(rep.pixelsWide), CGFloat(rep.pixelsHigh), CGFloat(48))
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w + 2 * pad), pixelsHigh: Int(h + 2 * pad),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let frame = NSRect(x: pad, y: pad, width: w, height: h)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.windowBackgroundColor.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    image.draw(in: frame)
    NSColor(white: 0, alpha: 0.12).setStroke()
    shape.lineWidth = 2
    shape.stroke()
    NSGraphicsContext.current = nil
    try! out.representation(using: .png, properties: [:])!.write(to: URL(filePath: "\(dst)/\(file)"))
}
SWIFT

ls -1 "$OUT"
