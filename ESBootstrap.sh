#!/usr/bin/env bash
# This will only work on Centos 7 (it has not been tested on other distros)

# Test if the VM can reach the internet to download packages
itest=$(ping -c 1 google.com | grep "bytes from")
while [ "$itest" == "" ]
do
    sleep 1
    itest=$(ping -c 1 google.com | grep "bytes from")
done
echo "online"

# Install Elasticsearch, Kibana, and Unzip
yum install -y unzip wget

# Get the GPG key
rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

# Add Elastic and Kibana and the Elastic Agent
# Download and install Ealsticsearch and Kibana change ver to whatever you want
# For me 8.0.0 is the latest we palce it in /vagrant to not download it again
# The -q flag is need to not spam stdout on the host machine
# We also pull the SHA512 hashes for you to check
VER=8.0.0
wget -nc -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VER-x86_64.rpm -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VER-x86_64.rpm.sha512 -P /vagrant

wget -nc -q https://artifacts.elastic.co/downloads/kibana/kibana-$VER-x86_64.rpm -P /vagrant
wget -nc -q https://artifacts.elastic.co/downloads/kibana/kibana-$VER-x86_64.rpm.sha512 -P /vagrant

rpm --install /vagrant/elasticsearch-$VER-x86_64.rpm
rpm --install /vagrant/kibana-$VER-x86_64.rpm

# Make the cert dir to prevent pop-up later
mkdir /tmp/certs/

# Config the instances file for cert gen the ip is 10.0.2.15
# IP addr is used again leter in kibana.yml
IP_ADDR=10.0.2.15
cat > /tmp/certs/instance.yml << EOF
instances:
  - name: 'elasticsearch'
    dns: [ 'elasticsearch.localdomain' ]
    ip: [ '$IP_ADDR' ]
  - name: 'kibana'
    dns: [ 'kibana.localdomain' ]
    ip: [ '$IP_ADDR' ]
EOF

# Make the certs and move them where they are needed
/usr/share/elasticsearch/bin/elasticsearch-certutil ca --pem --pass secret --out /tmp/certs/elastic-stack-ca.zip
unzip /tmp/certs/elastic-stack-ca.zip -d /tmp/certs/
/usr/share/elasticsearch/bin/elasticsearch-certutil cert --ca-cert /tmp/certs/ca/ca.crt -ca-key /tmp/certs/ca/ca.key --ca-pass secret --pem --in /tmp/certs/instance.yml --out /tmp/certs/certs.zip
unzip /tmp/certs/certs.zip -d /tmp/certs/

mkdir /etc/kibana/certs

cp /tmp/certs/ca/ca.crt /tmp/certs/elasticsearch/* /etc/elasticsearch/certs
cp /tmp/certs/ca/ca.crt /tmp/certs/kibana/* /etc/kibana/certs
cp -r /tmp/certs/* /root/

# This cp should be an unaliased cp to replace the ca.crt if it exists in the shared /vagrant dir
cp /tmp/certs/ca/ca.crt /vagrant

# Config and start Elasticsearch (we are also increasing the timeout for systemd to 500)
mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak

cat > /etc/elasticsearch/elasticsearch.yml << EOF
# ======================== Elasticsearch Configuration =========================
#
# ----------------------------------- Paths ------------------------------------
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
# ---------------------------------- Network -----------------------------------
network.host: $IP_ADDR
http.port: 9200
# --------------------------------- Discovery ----------------------------------
discovery.type: single-node
# ----------------------------------- X-Pack -----------------------------------
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.key: /etc/elasticsearch/certs/elasticsearch.key
xpack.security.transport.ssl.certificate: /etc/elasticsearch/certs/elasticsearch.crt
xpack.security.transport.ssl.certificate_authorities: [ "/etc/elasticsearch/certs/ca.crt" ]
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: /etc/elasticsearch/certs/elasticsearch.key
xpack.security.http.ssl.certificate: /etc/elasticsearch/certs/elasticsearch.crt
xpack.security.http.ssl.certificate_authorities: [ "/etc/elasticsearch/certs/ca.crt" ]
xpack.security.authc.api_key.enabled: true
EOF

sed -i 's/TimeoutStartSec=75/TimeoutStartSec=500/g' /lib/systemd/system/elasticsearch.service
systemctl daemon-reload
systemctl start elasticsearch
systemctl enable elasticsearch

# Gen the users and paste the output for later use
/usr/share/elasticsearch/bin/elasticsearch-reset-password -b -u kibana_system -a > /root/Kibpass.txt

# Add the Kibana password to the keystore
grep "New value:" /root/Kibpass.txt | awk '{print $3}' | sudo /usr/share/kibana/bin/kibana-keystore add --stdin elasticsearch.password

# Configure and start Kibana adding in the unique kibana_system keystore pass and gening the sec keys
cat > /etc/kibana/kibana.yml << EOF
# =========================== Kibana Configuration ============================
# -------------------------------- Network ------------------------------------
server.host: $IP_ADDR
server.port: 5601
# ------------------------------ Elasticsearch --------------------------------
elasticsearch.hosts: ["https://$IP_ADDR:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "\${elasticsearch.password}"
# ---------------------------------- Various -----------------------------------
server.ssl.enabled: true
server.ssl.certificate: "/etc/kibana/certs/kibana.crt"
server.ssl.key: "/etc/kibana/certs/kibana.key"
elasticsearch.ssl.certificateAuthorities: [ "/etc/kibana/certs/ca.crt" ]
# ---------------------------------- X-Pack ------------------------------------
xpack.security.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
xpack.encryptedSavedObjects.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
xpack.reporting.encryptionKey: "$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
EOF

systemctl start kibana
systemctl enable kibana

echo "Script done. To connect go to https://127.0.0.1:5601 on your host system"
echo "It will take 1-5 min for Kibana to come up"
echo "The elastic password will be displayed in the terminal you ran Vagrant from"
echo "Under the line --Security autoconfiguration information--"