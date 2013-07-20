#!/bin/bash
set -e

if [ ! -z $domain_var ] ; then
    echo "Installing GitLab for domain: $domain_var"
else 
    echo "Please pass domain_var"
    exit
fi

##sudo apt-get install -y build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev libmysqld-dev libmysqlclient-dev mysql-client
##
### Install Python
##sudo apt-get install -y python
##
##sudo apt-get remove -y ruby1.8
##
##CWD=`pwd`
##mkdir -p /tmp/ruby && cd /tmp/ruby
##curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz
##cd ruby-2.0.0-p247
##./configure
##make
##sudo make install
##cd $CWD
##
##sudo gem install bundler --no-ri --no-rdoc
##
#if [ `grep -c '^git:' /etc/passwd` == 0 ]; then
#    sudo adduser --disabled-login --gecos 'GitLab' git
#fi
#
### Go to home directory
#CWD=`pwd`
#cd /home/git
#
### Clone gitlab shell
#sudo -u git -H git clone https://github.com/gitlabhq/gitlab-shell.git
#
#cd gitlab-shell
#
### switch to right version
#sudo -u git -H git checkout v1.4.0
#
#sudo -u git -H cp config.yml.example config.yml
#
### Edit config and replace gitlab_url
### with something like 'http://domain.com/'
### sudo -u git -H editor config.yml
#echo 'Set host in config.yml'
#sudo sed -i "s/  host: localhost/  host: $domain_var/" config.yml
#
## Do setup
#echo "Do setup"
#sudo -u git -H ./bin/install
#cd $CWD

#==
#== 5. MySQL
#==

# in case existing installation
sudo apt-get --purge -y remove mysql-server*; sudo /usr/share/debconf/fix_db.pl

sudo apt-get install -y makepasswd # Needed to create a unique password non-interactively.
userPassword=$(makepasswd --char=10) # Generate a random MySQL password
# Note that the lines below creates a cleartext copy of the random password in /var/cache/debconf/passwords.dat
# This file is normally only readable by root and the password will be deleted by the package management system after install.
echo mysql-server mysql-server/root_password password $userPassword | sudo debconf-set-selections
echo mysql-server mysql-server/root_password_again password $userPassword | sudo debconf-set-selections
sudo apt-get install -y mysql-server mysql-client libmysqlclient-dev
echo "MYSQL root password: $userPassword"

# Create a user for GitLab
# do not type the 'mysql>', this is part of the prompt
# change $password in the command below to a real password you pick
db_password=$(makepasswd --char=10) # Generate a random MySQL password
mysql -u root -p"$userPassword" -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$db_password';"

# Create the GitLab production database
mysql -u root -p"$userPassword" -e 'CREATE DATABASE IF NOT EXISTS `gitlabhq_production` DEFAULT CHARACTER SET `utf8` COLLATE `utf8_unicode_ci`;'

# Grant the GitLab user necessary permissions on the table.
mysql -u root -p"$userPassword" -e ' GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON `gitlabhq_production`.* TO "gitlab"@"localhost";'

# Try connecting to the new database with the new user
sudo -u git -H mysql -u gitlab -p"$db_password" -D gitlabhq_production -e 'select 1'

# We'll install GitLab into home directory of the user "git"
CWD=`pwd`
cd /home/git
# Clone GitLab repository
sudo -u git -H rm -rf gitlab
sudo -u git -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab

# Go to gitlab dir
cd /home/git/gitlab

# Checkout to stable release
sudo -u git -H git checkout 5-3-stable

cd /home/git/gitlab

# Copy the example GitLab config
sudo -u git -H cp config/gitlab.yml.example config/gitlab.yml

# Make sure to change "localhost" to the fully-qualified domain name of your
# host serving GitLab where necessary
sudo sed -i "s/  host: localhost/  host: $domain_var/" /home/git/gitlab/config/gitlab.yml

# Make sure GitLab can write to the log/ and tmp/ directories
sudo chown -R git log/
sudo chown -R git tmp/
sudo chmod -R u+rwX  log/
sudo chmod -R u+rwX  tmp/

# Create directory for satellites
sudo -u git -H mkdir -p /home/git/gitlab-satellites

# Create directories for sockets/pids and make sure GitLab can write to them
sudo -u git -H mkdir -p tmp/pids/
sudo -u git -H mkdir -p tmp/sockets/
sudo chmod -R u+rwX  tmp/pids/
sudo chmod -R u+rwX  tmp/sockets/

# Create public/uploads directory otherwise backup will fail
sudo -u git -H mkdir -p public/uploads
sudo chmod -R u+rwX  public/uploads

# Copy the example Puma config
sudo -u git -H cp config/puma.rb.example config/puma.rb

# Enable cluster mode if you expect to have a high load instance
# Ex. change amount of workers to 3 for 2GB RAM server
#sudo -u git -H vim config/unicorn.rb

# Configure Git global settings for git user, useful when editing via web
# Edit user.email according to what is set in gitlab.yml
sudo -u git -H git config --global user.name "GitLab"
sudo -u git -H git config --global user.email "gitlab@localhost"

# Mysql
sudo -u git cp config/database.yml.mysql config/database.yml

# Make sure to update username/password in config/database.yml.
# You only need to adapt the production settings (first part).
# If you followed the database guide then please do as follows:
# Change 'root' to 'gitlab'
# Change 'secure password' with the value you have given to $password
# You can keep the double quotes around the password
#sudo -u git -H editor config/database.yml
sudo sed -i 's/"secure password"/"'$db_password'"/' config/database.yml

# Make config/database.yml readable to git only
sudo -u git -H chmod o-rwx config/database.yml

cd /home/git/gitlab

sudo gem install charlock_holmes --version '0.6.9.4'

# For MySQL (note, the option says "without ... postgres")
sudo -u git -H bundle install --deployment --without development test postgres unicorn aws

sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production

# Type 'yes' to create the database.

# When done you see 'Administrator account created:'

sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab

sudo update-rc.d gitlab defaults 21
