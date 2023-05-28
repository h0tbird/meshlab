# Hypervisor.framework

The drivers utilized on MacOS, specifically [HyperKit](https://github.com/moby/hyperkit) and [QEMU](https://www.qemu.org), rely on MacOS' [Hypervisor.framework](https://developer.apple.com/documentation/hypervisor) to manage the networking stack for the instances. When an instance is created, the `Hypervisor.framework` on the host employs MacOS' *'Internet Sharing'* mechanism to establish a virtual switch. Each instance is then connected to this switch with the subnet address 192.168.64.*. Furthermore, the host provides DHCP and DNS resolution services on this switch through the IP address 192.168.64.1, facilitated by the `bootpd` and `mDNSResponder` services running on the host machine. It is worth noting that attempting to manually edit the configuration file `/etc/bootpd.plist` is futile, as MacOS will regenerate it according to its own preferences.

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
