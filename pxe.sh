#!/usr/bin/env bash -eu

echo "Fetching netboot.xyz..."
git clone https://github.com/netbootxyz/netboot.xyz.git /tmp/netboot

echo "Copying overrides and custom menus..."
mkdir /tmp/netboot/custom
cp pxe/user_overrides.yml /tmp/netboot
cp -r pxe/custom/* /tmp/netboot/custom

echo "Building netboot.xyz..."
docker build -t localbuild -f /tmp/netboot/Dockerfile-build /tmp/netboot
docker run --rm -it -v /tmp/netboot:/buildout localbuild

echo "Uploading new build..."
scp /tmp/netboot/buildout/* josh@nas.gilman.io:/volume1/pxe
scp -r /tmp/netboot/buildout/custom josh@nas.gilman.io:/volume1/pxe
scp /tmp/netboot/buildout/ipxe/* josh@nas.gilman.io:/volume1/tftp

echo "Cleaning up..."
rm -rf /tmp/netboot