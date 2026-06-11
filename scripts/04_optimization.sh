sudo tee /etc/default/zram-tools > /dev/null << 'ZRAM'
CORES=$(nproc)
ALGO=zstd
PERCENT=100
PRIORITY=100
ZRAM
sudo swapoff /dev/zram0 2>/dev/null || true
sudo systemctl restart zramswap.service

