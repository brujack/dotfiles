Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu/focal64'

  config.vm.synced_folder ".", "/dotfiles", mount_options: ["ro"]

  # disable default synced folder
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # install packages. The provisioner runs as root with no tty, so a debconf or
  # conffile prompt would fail the provision rather than wait; the conffile
  # options are spelled out because this script cannot source lib/constants.sh.
  config.vm.provision "shell", inline: <<-EOS
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
    DEBIAN_FRONTEND=noninteractive apt install -y \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      git make build-essential libssl-dev zlib1g-dev \
      libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
      libncurses5-dev
  EOS

end
