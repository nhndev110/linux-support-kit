```bash
sudo swapoff -a
sudo vgchange -an
sudo dmsetup remove_all
sudo wipefs -a /dev/nvme0n1
sudo sgdisk --zap-all /dev/nvme0n1
```
