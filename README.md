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

List images in pull-through registries:
```
curl -s 192.168.64.1:5001/v2/_catalog | jq
curl -s 192.168.64.1:5002/v2/_catalog | jq
curl -s 192.168.64.1:5003/v2/_catalog | jq
```

List image tags in pull-through registries:
```
curl -s 192.168.64.1:5001/v2/calico/cni/tags/list | jq
curl -s 192.168.64.1:5002/v2/argoproj/argocd/tags/list | jq
curl -s 192.168.64.1:5003/v2/resf/istio/pilot/tags/list | jq
```

```
k --context kube-01 -n httpbin exec -it httpbin-69d46696d6-c6p6m -c istio-proxy -- sudo tcpdump dst port 8080 -A
k --context kube-02 -n httpbin exec -it httpbin-7f859459c6-lkfbr -c istio-proxy -- sudo tcpdump dst port 8080 -A
```

```
k --context kube-01 -n httpbin exec -it sleep-5f694bf9d6-vqbfv -- curl http://httpbin.httpbin:5000/get
k --context kube-02 -n httpbin exec -it sleep-74456b78d-8hwd7 -- curl http://httpbin.httpbin:5000/get
```

- If `STRICT` mTLS then requests are encrypted and balanced across both clusters.
- If `DISABLE` mTLS then requests are not encrypted and local to each cluster.

