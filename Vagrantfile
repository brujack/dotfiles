Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu/focal64'

  config.vm.synced_folder ".", "/dotfiles", mount_options: ["ro"]

  # disable default synced folder
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # install packages
  config.vm.provision "shell", inline: <<-EOS
    apt update -y
    apt dist-upgrade -y
    apt install -y git make build-essential libssl-dev zlib1g-dev \
      libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
      libncurses5-dev
  EOS

end
