# it-works-on-my-machine
Local k8s on arm64

```
multipass get local.driver
qemu
```

```
qemu-system-aarch64 \
  -machine virt,highmem=off \
  -accel hvf \
  -drive file=/Library/Application Support/com.canonical.multipass/bin/../Resources/qemu/edk2-aarch64-code.fd,if=pflash,format=raw,readonly=on \
  -cpu cortex-a72 \
  -nic vmnet-shared,model=virtio-net-pci,mac=52:54:00:6a:db:ad \
  -device virtio-scsi-pci,id=scsi0 \
  -drive file=/var/root/Library/Application Support/multipassd/qemu/vault/instances/kube-02/ubuntu-20.04-server-cloudimg-arm64.img,if=none,format=qcow2,discard=unmap,id=hda \
  -device scsi-hd,drive=hda,bus=scsi0.0 \
  -smp 2 \
  -m 2048M \
  -qmp stdio \
  -chardev null,id=char0 \
  -serial chardev:char0 \
  -nographic \
  -cdrom /var/root/Library/Application Support/multipassd/qemu/vault/instances/kube-02/cloud-init-config.iso
```

```
calicoctl get ippool -o wide

```
