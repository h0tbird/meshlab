# Hypervisor.framework

The drivers used on MacOS (`HyperKit` and `QEMU`) employ MacOS’
`Hypervisor.framework`. This framework manages the networking stack for the
instances. On creation of an instance, `Hypervisor.framework` on the host uses
MacOS’ “Internet Sharing” mechanism to create a virtual switch and connect each
instance to it (subnet 192.168.64.*) and provide DHCP and DNS resolution on
this switch at 192.168.64.1 (via `bootpd` & `mDNSResponder` services running on
the host); this is configured by an auto-generated file `/etc/bootpd.plist` -
but editing this is pointless as MacOS re-generates it as it desires.

Is the `bootpd` DHCP server alive?
```console
sudo lsof -iUDP:67 -n -P
```

Start it:
```console
sudo launchctl load -w /System/Library/LaunchDaemons/bootps.plist
```

Flush all DHCP leases:
```console
sudo launchctl stop com.apple.bootpd
sudo rm -f /var/db/dhcpd_leases
sudo launchctl start com.apple.bootpd
```
