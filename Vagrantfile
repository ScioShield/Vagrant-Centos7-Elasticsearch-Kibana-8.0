Vagrant.configure("2") do |config|
  config.vm.box = "bento/centos-7"
  config.vm.provision :shell, path: "ESBootstrap.sh"
  config.vm.network "forwarded_port", guest: 5601, host: 5601, host_ip: "127.0.0.1"
  config.vm.provider "virtualbox" do |vb|
    vb.cpus = "4"
    vb.memory = "8192"
  end
end