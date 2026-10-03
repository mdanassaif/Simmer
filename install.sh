#!/bin/zsh -f
# Installs awake + asleep into ~/.local/bin, builds Awake.app (the Control
# Center toggle) in Release, installs it to ~/Applications and opens it.
setopt err_exit pipe_fail no_unset
cd ${0:A:h}

bin=~/.local/bin
app=~/Applications/Awake.app
built=build/Build/Products/Release/Awake.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

print "==> awake, asleep -> $bin"
mkdir -p $bin
cp bin/awake $bin/.awake.new
chmod 755 $bin/.awake.new
mv -f $bin/.awake.new $bin/awake   # atomic, so a running watcher keeps its copy
ln -sfn awake $bin/asleep

print "==> xcodegen"
if ! command -v xcodegen >/dev/null; then
  print -u2 "install.sh: xcodegen not found; brew install xcodegen"
  exit 1
fi
xcodegen generate --quiet

print "==> xcodebuild (Release)"
xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build

print "==> $app"
pkill -x Awake 2>/dev/null || true
pkill -f 'AwakeControl.appex' 2>/dev/null || true
mkdir -p ${app:h}
rm -rf $app
ditto $built $app
$lsregister -u $built 2>/dev/null || true   # one registered copy, one toggle in the gallery
$lsregister -f $app
open -g $app

print "\nDone. Add the toggle: Control Center > Edit Controls > Awake."
if [[ :$PATH: != *:$bin:* ]]; then
  print "Add $bin to your PATH:  print 'path=(~/.local/bin \$path)' >> ~/.zshrc"
fi
if ! sudo -n -l 2>/dev/null | grep -q 'NOPASSWD:.*/usr/bin/pmset -a disablesleep 1'; then
  rule=$PWD/sudoers.d/awake
  print "\nSo awake, the watcher and the toggle never need a password, install the sudoers rule:"
  print "  sudo visudo -cf $rule && sudo install -m 0440 -o root -g wheel $rule /etc/sudoers.d/awake"
fi
