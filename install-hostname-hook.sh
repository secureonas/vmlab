#!/bin/bash
# Run this ONCE inside each master image, before taking the golden snapshot.
# It installs a oneshot unit that reads guestinfo.hostname (written into the
# clone's .vmx by start-vm.ps1) and renames the guest at boot.
#
#   sudo bash install-hostname-hook.sh
#
set -e

sudo tee /usr/local/sbin/set-guest-hostname.sh >/dev/null <<'EOF'
#!/bin/bash
RPC=$(command -v vmware-rpctool) || RPC=$(command -v vmtoolsd) || exit 0
case "$RPC" in
  *vmtoolsd) NAME=$("$RPC" --cmd "info-get guestinfo.hostname" 2>/dev/null) ;;
  *)         NAME=$("$RPC" "info-get guestinfo.hostname" 2>/dev/null) ;;
esac
[ -z "$NAME" ] && exit 0
[ "$(hostnamectl --static)" = "$NAME" ] && exit 0
hostnamectl set-hostname "$NAME"
sed -i "s/^127.0.1.1.*/127.0.1.1 $NAME/" /etc/hosts 2>/dev/null
exit 0
EOF
sudo chmod 755 /usr/local/sbin/set-guest-hostname.sh

sudo tee /etc/systemd/system/set-guest-hostname.service >/dev/null <<'EOF'
[Unit]
Description=Set hostname from VMware guestinfo
Requires=vmtoolsd.service
After=vmtoolsd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/set-guest-hostname.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable set-guest-hostname.service

echo
echo "Installed. On this master the unit stays inactive (no guestinfo.hostname set)."
echo "Now: sudo shutdown -h now, then take the golden snapshot from the host."
