#! /bin/bash
echo "-- Configure user cloudera with passwordless"
useradd cloudera -d /home/cloudera -p cloudera
sudo usermod -aG wheel cloudera
sudo cp /etc/sudoers /etc/sudoers.bkp
sudo rm -rf /etc/sudoers
sudo sed '/^#includedir.*/a cloudera ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.bkp > /etc/sudoers
echo "-- Configure and optimize the OS"
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.d/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.d/rc.local
# add tuned optimization https://www.cloudera.com/documentation/enterprise/6/6.2/topics/cdh_admin_performance.html
echo  "vm.swappiness = 1" >> /etc/sysctl.conf
sudo sysctl vm.swappiness=1
sudo timedatectl set-timezone UTC

echo "-- Install Java OpenJDK8 and other tools"
sudo yum install -y java-1.8.0-openjdk-devel vim wget curl git bind-utils rng-tools
sudo yum install -y epel-release
sudo yum install -y python-pip

sudo cp /usr/lib/systemd/system/rngd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start rngd
sudo systemctl enable rngd

echo "-- Installing requirements for Stream Messaging Manager"
sudo yum install -y gcc-c++ make
sudo curl -sL https://rpm.nodesource.com/setup_10.x | sudo -E bash -
sudo yum install nodejs -y
sudo npm install forever -g

echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
sudo systemctl restart chronyd

echo "-- Configure networking"
PUBLIC_IP=`curl https://api.ipify.org/`
hostnamectl set-hostname `hostname -f`
sudo echo "`hostname -I` `hostname`" >> /etc/hosts
sudo sed -i "s/HOSTNAME=.*/HOSTNAME=`hostname`/" /etc/sysconfig/network
sudo systemctl disable firewalld
sudo systemctl stop firewalld
sudo setenforce 0
sudo sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

echo "-- Install CM and MariaDB"

## CM 7
sudo wget https://archive.cloudera.com/cm7/7.1.1/redhat7/yum/cloudera-manager-trial.repo -P /etc/yum.repos.d/

# MariaDB 10.1
sudo cat - >/etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF


sudo yum clean all
sudo rm -rf /var/cache/yum/
sudo yum repolist

## CM
sudo yum install -y cloudera-manager-agent cloudera-manager-daemons cloudera-manager-server

## MariaDB
sudo yum install -y MariaDB-server MariaDB-client
sudo cat conf/mariadb.config > /etc/my.cnf

echo "--Enable and start MariaDB"
sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "-- Install JDBC connector"
cd ~
sudo wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.46.tar.gz -P ~
sudo tar zxf ~/mysql-connector-java-5.1.46.tar.gz -C ~
sudo mkdir -p /usr/share/java/
sudo cp ~/mysql-connector-java-5.1.46/mysql-connector-java-5.1.46-bin.jar /usr/share/java/mysql-connector-java.jar
sudo rm -rf ~/mysql-connector-java-5.1.46*

echo "-- Create DBs required by CM"
sudo mysql -u root < scripts/create_db.sql

echo "-- Secure MariaDB"
sudo mysql -u root < scripts/secure_mariadb.sql

echo "-- Prepare CM database 'scm'"
sudo /opt/cloudera/cm/schema/scm_prepare_database.sh mysql scm scm cloudera

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
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo yum install -y postgresql96
sudo yum install -y postgresql96-server
sudo pip install psycopg2==2.7.5 --ignore-installed

echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
sudo /usr/pgsql-9.6/bin/postgresql96-setup initdb

sudo cat conf/pg_hba.conf > /var/lib/pgsql/9.6/data/pg_hba.conf
sudo cat conf/postgresql.conf > /var/lib/pgsql/9.6/data/postgresql.conf

echo "--Enable and start pgsql"
sudo systemctl enable postgresql-9.6
sudo systemctl start postgresql-9.6

echo "-- Create DBs required by CM"
sudo -u postgres psql <<EOF 
CREATE DATABASE ranger;
CREATE USER ranger WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE ranger TO ranger;
CREATE DATABASE das;
CREATE USER das WITH PASSWORD 'cloudera';
GRANT ALL PRIVILEGES ON DATABASE das TO das;
EOF


echo "-- Install CSDs"
sudo wget https://archive.cloudera.com/CFM/csd/1.0.1.0/NIFI-1.9.0.1.0.1.0-12.jar -P /opt/cloudera/csd/
sudo wget https://archive.cloudera.com/CFM/csd/1.0.1.0/NIFICA-1.9.0.1.0.1.0-12.jar -P /opt/cloudera/csd/
sudo wget https://archive.cloudera.com/CFM/csd/1.0.1.0/NIFIREGISTRY-0.3.0.1.0.1.0-12.jar -P /opt/cloudera/csd/
# CDSW CSD: must update descriptors so it can install on CR7
sudo wget https://archive.cloudera.com/cdsw1/1.6.1/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH6-1.6.1.jar -P /data/cdswjar
sudo cd /data/cdswjar/
sudo mv CLOUDERA_DATA_SCIENCE_WORKBENCH-CDH6-1.6.1.jar ~
cd ..
# install local CSDs
sudo mv ~/*.jar /opt/cloudera/csd/
sudo mv /home/centos/*.jar /opt/cloudera/csd/
sudo chown cloudera-scm:cloudera-scm /opt/cloudera/csd/*
sudo chmod 644 /opt/cloudera/csd/*

echo "-- Install local parcels"
sudo mv ~/*.parcel ~/*.parcel.sha /opt/cloudera/parcel-repo/
sudo mv /home/centos/*.parcel /home/centos/*.parcel.sha /opt/cloudera/parcel-repo/
sudo chown cloudera-scm:cloudera-scm /opt/cloudera/parcel-repo/*

echo "-- Enable passwordless root login via rsa key"
sudo ssh-keygen -f ~/myRSAkey -t rsa -N ""
sudo mkdir ~/.ssh
sudo cat ~/myRSAkey.pub >> ~/.ssh/authorized_keys
sudo chmod 400 ~/.ssh/authorized_keys
sudo ssh-keyscan -H `hostname` >> ~/.ssh/known_hosts
sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
sudo systemctl restart sshd

echo "-- Start CM, it takes about 2 minutes to be ready"
sudo systemctl start cloudera-scm-server

while [ `curl -s -X GET -u "admin:admin"  http://localhost:7180/api/version` -z ] ;
    do
    echo "waiting 10s for CM to come up..";
    sleep 10;
done
