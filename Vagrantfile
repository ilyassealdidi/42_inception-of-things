# -*- mode: ruby -*-
# vi: set ft=ruby :

# ============================================================
#  Bonus part - Vagrantfile
#  Single VM sized to run K3d + Argo CD + GitLab (Helm chart)
#
#  >>> Replace "login" below with your actual login (e.g. "wil") <<<
# ============================================================

LOGIN     = "ezahiri"          # <-- CHANGE THIS
HOSTNAME  = "#{LOGIN}S"      # subject convention: login + "S"
STATIC_IP = "192.168.56.110"

Vagrant.configure("2") do |config|
  # Latest stable Debian 12 (Bookworm) - swap for "ubuntu/jammy64" if you prefer Ubuntu 22.04
  config.vm.box = "debian/bookworm64"
  config.vm.box_check_update = true

  config.vm.define HOSTNAME do |node|
    node.vm.hostname = HOSTNAME

    # Dedicated static IP, as required by the subject
    node.vm.network "private_network", ip: STATIC_IP

    # Passwordless SSH: Vagrant generates a per-VM keypair automatically (modern default)
    node.ssh.forward_agent = true

    # Disable the default "." -> /vagrant shared folder.
    # Required when running Vagrant from WSL2 on a non-DrvFs path
    # (i.e. your project isn't under /mnt/c/...).
    node.vm.synced_folder ".", "/vagrant", disabled: true

    node.vm.provider "virtualbox" do |vb|
      vb.name   = HOSTNAME
      vb.memory = 8192   # 8 GB - GitLab Helm chart needs headroom, bump to 12288 if host allows
      vb.cpus   = 4
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end

    node.vm.provision "shell", inline: <<-SHELL
      set -e
      ARCH="$(uname -m)"
      [ "$ARCH" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"

      echo "===== [1/4] Installing git ====="
      if ! command -v git &> /dev/null; then
        apt-get updatels
        apt-get install -y git
        echo "git installed."
      else
        echo "git already installed, skipping."
      fi

      echo "===== [2/4] Installing Docker ====="
      if ! command -v docker &> /dev/null; then
        . /etc/os-release
        apt-get update
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        usermod -aG docker vagrant
        echo "Docker installed."
      else
        echo "Docker already installed, skipping."
      fi

      echo "===== [3/4] Installing kubectl ====="
      if ! command -v kubectl &> /dev/null; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        echo "kubectl installed."
      else
        echo "kubectl already installed, skipping."
      fi

      echo "===== [4/4] Installing K3d ====="
      if ! command -v k3d &> /dev/null; then
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
        echo "K3d installed."
      else
        echo "K3d already installed, skipping."
      fi

      echo ""
      echo "===== Bootstrap complete: git, Docker, kubectl, K3d installed ====="
    SHELL
  end
end