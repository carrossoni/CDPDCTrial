#! /bin/bash
echo "-- Configure user cloudera with passwordless and pem file"
useradd cloudera -d /home/cloudera -p cloudera
sudo usermod -aG wheel cloudera
cp /etc/sudoers /etc/sudoers.bkp
rm -rf /etc/sudoers
sed '/^#includedir.*/a cloudera ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.bkp > /etc/sudoers
ssh-keygen -t rsa -b 2048 -P '' -f ~/.ssh/clouderakey
cd /home/vagrant/.ssh/
cat clouderakey.pub >> authorized_keys
chmod 0600 authorized_keys
openssl rsa -in clouderakey -outform pem > ~/clouderakey.pem
chmod 0400 ~/clouderakey.pem
cp ~/cloudera.pem /home/cloudera
cp ~/cloudera.pem /home/vagrant
cp -r /home/vagrant/.ssh /home/cloudera/.ssh
cd ~

echo "-- Configure and optimize the OS"
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.d/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.d/rc.local
# add tuned optimization https://www.cloudera.com/documentation/enterprise/6/6.2/topics/cdh_admin_performance.html
echo  "vm.swappiness = 1" >> /etc/sysctl.conf
sysctl vm.swappiness=1
timedatectl set-timezone UTC

echo "-- Install Java OpenJDK8 and other tools"
yum install -y java-1.8.0-openjdk-devel vim wget curl git bind-utils rng-tools
yum install -y epel-release
yum install -y python-pip

cp /usr/lib/systemd/system/rngd.service /etc/systemd/system/
systemctl daemon-reload
systemctl start rngd
systemctl enable rngd

echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
systemctl restart chronyd

sudo /etc/init.d/network restart

echo "-- Configure networking"
#PUBLIC_IP=`curl https://api.ipify.org/`
#hostnamectl set-hostname `hostname -f`
#sed -i$(date +%s).bak '/^[^#]*cloudera/s/^/# /' /etc/hosts
sed -i$(date +%s).bak '/^[^#]*::1/s/^/# /' /etc/hosts
#sed -i$(date +%s).bak 's/127\.0\.0\.1/& cloudera /' /etc/hosts
echo "`host cloudera |grep address | awk '{print $4}'` `hostname` `hostname`" >> /etc/hosts
#sed -i "s/HOSTNAME=.*/HOSTNAME=`hostname`/" /etc/sysconfig/network
systemctl disable firewalld
systemctl stop firewalld
service firewalld stop
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

echo  "Disabling IPv6"
echo "net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
      net.ipv6.conf.lo.disable_ipv6 = 1
      net.ipv6.conf.eth0.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p

sudo service network-manager restart

echo "-- Install CM and MariaDB"

# CM 7
wget https://archive.cloudera.com/cm7/7.1.4/redhat7/yum/cloudera-manager-trial.repo -P /etc/yum.repos.d/

# MariaDB 10.1
cat - >/etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF


yum clean all
rm -rf /var/cache/yum/
yum repolist

## CM
yum install -y cloudera-manager-agent cloudera-manager-daemons cloudera-manager-server

#sed -i$(date +%s).bak '/^[^#]*server_host/s/^/# /' /etc/cloudera-scm-agent/config.ini
#sed -i$(date +%s).bak '/^[^#]*listening_ip/s/^/# /' /etc/cloudera-scm-agent/config.ini
#sed -i$(date +%s).bak "/^# server_host.*/i server_host=$(hostname)" /etc/cloudera-scm-agent/config.ini
#sed -i$(date +%s).bak "/^# listening_ip=.*/i listening_ip=$(host cloudera |grep address | awk '{print $4}')" /etc/cloudera-scm-agent/config.ini

service cloudera-scm-agent restart

## MariaDB
yum install -y MariaDB-server MariaDB-client
cat /root/CDPDCTrial/conf/mariadb.config > /etc/my.cnf

echo "--Enable and start MariaDB"
systemctl enable mariadb
systemctl start mariadb

echo "-- Install JDBC connector"
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz -P ~
tar zxf ~/mysql-connector-java-5.1.46.tar.gz -C ~
mkdir -p /usr/share/java/
cp ~/mysql-connector-java-5.1.46/mysql-connector-java-5.1.46-bin.jar /usr/share/java/mysql-connector-java.jar
rm -rf ~/mysql-connector-java-5.1.46*

echo "-- Create DBs required by CM"
mysql -u root < /root/CDPDCTrial/scripts/create_db.sql

echo "-- Secure MariaDB"
mysql -u root < /root/CDPDCTrial/scripts/secure_mariadb.sql

echo "-- Prepare CM database 'scm'"
/opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm cloudera

## PostgreSQL
#yum install -y postgresql-server python-pip
#pip install psycopg2==2.7.5 --ignore-installed
#echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
#sudo su -l postgres -c "postgresql-setup initdb"
#cat conf/pg_hba.conf > /var/lib/pgsql/data/pg_hba.conf
#cat conf/postgresql.conf > /var/lib/pgsql/data/postgresql.conf
#echo "--Enable and start pgsql"
#systemctl enable postgresql
#systemctl restart postgresql

## PostgreSQL see: https://www.postgresql.org/download/linux/redhat/
yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install -y postgresql96
yum install -y postgresql96-server
pip install psycopg2==2.7.5 --ignore-installed

echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
/usr/pgsql-9.6/bin/postgresql96-setup initdb

cat /root/CDPDCTrial/conf/pg_hba.conf > /var/lib/pgsql/9.6/data/pg_hba.conf
cat /root/CDPDCTrial/conf/postgresql.conf > /var/lib/pgsql/9.6/data/postgresql.conf

echo "--Enable and start pgsql"
systemctl enable postgresql-9.6
systemctl start postgresql-9.6

echo "-- Create DBs required by CM"
sudo -u postgres psql <<EOF 
CREATE DATABASE ranger;
CREATE USER ranger WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE ranger TO ranger;
CREATE DATABASE das;
CREATE USER das WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE das TO das;
EOF


echo "-- Enable passwordless root login via rsa key"
ssh-keygen -f ~/myRSAkey -t rsa -N ""
mkdir ~/.ssh
cat ~/myRSAkey.pub >> ~/.ssh/authorized_keys
chmod 400 ~/.ssh/authorized_keys
ssh-keyscan -H `hostname` >> ~/.ssh/known_hosts
sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
systemctl restart sshd

echo "-- Prepare parcels dirs"

chmod -R 777 /opt/cloudera/parcel-repo
chmod -R 777 /opt/cloudera/parcel-cache
chmod -R 777 /opt/cloudera/csd
chmod -R 777 /opt/cloudera/parcels

echo "-- Start CM, it takes about 2 minutes to be ready"
systemctl start cloudera-scm-server

while [ `curl -s -X GET -u "admin:admin"  http://localhost:7180/api/version` -z ] ;
    do
    echo "waiting 10s for CM to come up..";
    sleep 10;
done

echo "-- Now CM is started and the next step is to automate using the CM API"

pip install cm_client

sed -i "s/YourHostname/`hostname -f`/g" ~/CDPDCTrial/scripts/create_cluster.py

mkdir /data
mkdir /data/dfs
chmod -R 777 /data

python ~/CDPDCTrial/scripts/create_cluster.py ~/CDPDCTrial/conf/cdpsandbox.json

sudo usermod cloudera -G hadoop
sudo -u hdfs hdfs dfs -mkdir /user/cloudera
sudo -u hdfs hdfs dfs -chown cloudera:hadoop /user/cloudera
sudo -u hdfs hdfs dfs -mkdir /user/admin
sudo -u hdfs hdfs dfs -chown admin:hadoop /user/admin
sudo -u hdfs hdfs dfs -chmod -R 0755 /tmp
