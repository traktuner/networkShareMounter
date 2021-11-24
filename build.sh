#!/bin/bash

if [! -test $1 ]; then
	echo "please use correcet parameters: $0 identifier version signing_certificate"
	exit 1
fi

identifier=$1
version=`echo $2 | sed "s/v//g"`
developerid=$3

( cd .. ; /usr/bin/xcodebuild install )

/usr/bin/pkgbuild --root "/tmp/networkShareMounter.dst/" \
--identifier ${identifier} \
--version ${version} \
--install-location "/" \
--sign "${developerid}" \
"/tmp/networkShareMounter.pkg"
rm -rf /tmp/networkShareMounter.dst

# xcodebuild install

# pkgbuild --root "/tmp/networkShareMounter.dst/" \
# --identifier "de.uni-erlangen.rrze.networkShareMounter" \
# --version "1.0.5" \
# --install-location "/" \
# --sign "Developer ID Installer: Universitaet Erlangen-Nuernberg RRZE (C8F68RFW4L)" \
# "/tmp/networkShareMounter.pkg"

# rm -rf /tmp/networkShareMounter.dst


