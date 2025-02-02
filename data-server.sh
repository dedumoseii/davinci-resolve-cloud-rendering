#!/bin/bash

# Install Docker

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


# Setting up Storage:

# Variables

DRIVE="/dev/sdb"  # Replace with the correct drive identifier
PARTITION="${DRIVE}1"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

# Step 1: Unmount the drive (if mounted)
echo "Unmounting $DRIVE if mounted..."
umount "$DRIVE"* 2>/dev/null

# Step 2: Create a new partition table
echo "Creating a new GPT partition table on $DRIVE..."
parted -s "$DRIVE" mklabel gpt

# Step 3: Create a single ext4 partition
echo "Creating a new ext4 partition..."
parted -s "$DRIVE" mkpart primary ext4 0% 100%

# Step 4: Format the partition as ext4
echo "Formatting the partition as ext4..."
mkfs.ext4 -L store "$PARTITION"


# Step 5: Create a mount point and mount the partition
MOUNT_POINT="/mnt/store"
echo "Creating mount point $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
mount "$PARTITION" "$MOUNT_POINT"

# Step 6: Update /etc/fstab for automatic mounting
echo "Updating /etc/fstab..."
UUID=$(blkid -s UUID -o value "$PARTITION")
echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab

echo "Partitioning and formatting complete. $PARTITION is mounted at $MOUNT_POINT."

# user name for sftp and samba shares
USER="davinci"
MOUNT=$MOUNT_POINT

cd $MOUNT
mkdir sftp-samba

SHAREDIR="$MOUNT/sftp-samba"

# Setup permissions

sudo useradd $USER
sudo passwd $USER

sudo chown root:root $MOUNT
sudo chown $USER:$USER $SHAREDIR
sudo chmod 777 $SHAREDIR

# Samba Setup

sudo apt update
sudo apt-get install -y samba samba-common-bin

sudo tee /etc/samba/smb.conf <<EOF
[global]

   workgroup = WORKGROUP
   server string = %h server (Samba, Ubuntu)

   protocol = SMB3
   security = user
   netbios name = sftpserver
   client min protocol = SMB3
   client max protocol = SMB3
   client smb encrypt = required
   client signing = required
   server min protocol = SMB3
   server max protocol = SMB3
   ntlm auth = ntlmv2-only


   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   usershare allow guests = yes

[RUSHES]
    comment = RUSHES
    path = /mnt/store/sftp-samba
    read only = no
    writable = yes
    browsable = yes
    guest ok = yes
    create mode = 0777
    directory mode = 0777
    force user = nobody
EOF

usermod -aG sambashare $USER
sudo smbpasswd -a $USER

sudo systemctl restart smbd nmbd


# until this point all above is working

# FileBrowser setup


# Create Dirs
cd
mkdir -p filebrowser/config
mkdir -p filebrowser/nginx
mkdir -p filebrowser/certs

cd filebrowser

# Create settings.json for filebrowser
sudo tee -a ./config/settings.json <<EOF
{
  "port": 80,
  "baseURL": "cudoupload.rushesfolder",
  "address": "",
  "log": "stdout",
  "database": "/config/filebrowser.db",
  "root": "/srv"
}
EOF

# Generate Self-Signed Certs for cudoupload.rushesfolder

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./certs/cudoupload.key \
  -out ./certs/cudoupload.crt \
  -subj "/CN=cudoupload.rushesfolder"

# Write nginx config to file, the config will pass traffic to the filebrowser container
# it uses the custom cert generated previously for communication

sudo tee -a ./nginx/cudoupload.conf <<EOF
server {
    listen 443 ssl;
    server_name cudoupload.rushesfolder;

    ssl_certificate /etc/ssl/certs/cudoupload.crt;
    ssl_certificate_key /etc/ssl/private/cudoupload.key;

    client_max_body_size 0; # Remove file upload size limit

    location / {
        proxy_pass http://filebrowser:80; # Proxy to FileBrowser container
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name cudoupload.rushesfolder;

    return 301 https://\$host\$request_uri; # Redirect HTTP to HTTPS
}
EOF

# Generate a Docker Compose file:
SHAREDIR=/mnt/store/sftp-samba

sudo tee -a ./docker-compose.yaml <<EOF
services:
  filebrowser:
    image: filebrowser/filebrowser
    container_name: filebrowser
    volumes:
      - ./config:/config
      - $SHAREDIR:/srv
    user: "${UID}:${GID}"

  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "443:443"  # Expose HTTPS
      - "80:80"
    volumes:
      - ./nginx:/etc/nginx/conf.d
      - ./certs:/etc/ssl/certs
      - ./certs:/etc/ssl/private
    depends_on:
      - filebrowser
EOF

sudo docker compose up -d

# all above is working

# breaker
# sFTP setup

SHAREDIR=/mnt/store/sftp-samba

sudo addgroup sftp
sudo usermod -aG sftp $USER

sudo tee -a /etc/ssh/sshd_config <<EOF
Match group sftp
ChrootDirectory $SHAREDIR
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
ForceCommand internal-sftp
EOF

#sudo tee -a /etc/ssh/sshd_config <<EOF
#PermitRootLogin no
#PasswordAuthentication yes
#EOF

sudo systemctl restart ssh